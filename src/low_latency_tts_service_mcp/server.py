"""FastAPI server that queues Kokoro TTS.cpp generation and playback."""

from __future__ import annotations

import concurrent.futures
import dataclasses
import datetime
import json
import logging
import queue
import threading
import time
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import APIRouter, FastAPI, HTTPException, Request
from fastapi.responses import Response
from pydantic import BaseModel

from low_latency_tts_service_mcp.tts import (
    AudioPlayer,
    KokoroRuntimeConfig,
    PlaybackJob,
    clean_text,
    generate_wav,
    kokoro_voices,
    load_config,
    load_tts_model,
    make_output_path,
    simplify_punctuation,
    unload_tts_model,
    validate_runtime_config,
)

logger = logging.getLogger("kokoro-tts-server")

STATUS_TTL_SECONDS: int = 3600


@dataclasses.dataclass(frozen=True)
class WorkItem:
    """A queued TTS request for the audio worker."""

    message_id: str
    text: str
    voice: str
    audio: concurrent.futures.Future[bytes]


@dataclasses.dataclass
class MessageStatus:
    """Lifecycle record for one queued message."""

    message_id: str
    status: str
    text: str
    audio_file: str | None
    error: str | None
    completed_at: float | None


class ServerState:
    """Mutable server state shared between endpoints and the worker."""

    def __init__(
        self,
        runtime: KokoroRuntimeConfig,
        output_dir: Path,
        voices: list[str],
        default_voice: str,
        sample_rate: int,
        lead_silence_ms: int,
        simplify_punctuation_enabled: bool,
        save_wav: bool,
    ) -> None:
        """Initialize server state from fully validated settings."""
        self.runtime = runtime
        self.output_dir = output_dir
        self.voices = voices
        self.default_voice = default_voice
        self.sample_rate = sample_rate
        self.lead_silence_ms = lead_silence_ms
        self.simplify_punctuation_enabled = simplify_punctuation_enabled
        self.save_wav = save_wav
        self.work_queue: queue.Queue[WorkItem | None] = queue.Queue()
        self.statuses: dict[str, MessageStatus] = {}
        self.status_lock = threading.Lock()
        self._counter = 0
        self._counter_lock = threading.Lock()

    def next_message_id(self) -> str:
        """Generate a unique message ID."""
        with self._counter_lock:
            self._counter += 1
            counter = self._counter
        timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        return f"msg_{timestamp}_{counter:03d}"

    def evict_expired(self) -> None:
        """Remove completed or failed status entries older than the status TTL."""
        now = time.time()
        with self.status_lock:
            expired = [
                message_id
                for message_id, status in self.statuses.items()
                if status.completed_at is not None and (now - status.completed_at) > STATUS_TTL_SECONDS
            ]
            for message_id in expired:
                del self.statuses[message_id]


class SayRequest(BaseModel):
    """Request body for POST /say."""

    text: str
    voice: str | None = None


class StatusResponse(BaseModel):
    """Response body for GET /status/{message_id}."""

    message_id: str
    status: str
    text: str
    audio_file: str | None
    error: str | None


class VoicesResponse(BaseModel):
    """Response body for GET /voices."""

    voices: list[str]
    default_voice: str


class HealthResponse(BaseModel):
    """Response body for GET /health."""

    status: str


router = APIRouter()


@router.get("/health")
def health() -> HealthResponse:
    """Return server liveness."""
    return HealthResponse(status="ok")


@router.get("/voices")
def voices(request: Request) -> VoicesResponse:
    """List available Kokoro voices."""
    state: ServerState = request.app.state.server
    return VoicesResponse(voices=state.voices, default_voice=state.default_voice)


@router.post("/say")
def say(request: Request, body: SayRequest) -> Response:
    """Queue text for Kokoro synthesis and playback, then return the WAV once it is generated."""
    state: ServerState = request.app.state.server

    cleaned = clean_text(body.text)
    if not cleaned:
        raise HTTPException(status_code=422, detail="Text is empty after cleaning")

    if state.simplify_punctuation_enabled:
        cleaned = simplify_punctuation(cleaned)

    voice = body.voice if body.voice else state.default_voice
    if voice not in state.voices:
        raise HTTPException(
            status_code=400,
            detail=f"Voice '{voice}' not available. Available voices: {', '.join(state.voices)}",
        )

    message_id = state.next_message_id()
    state.evict_expired()

    with state.status_lock:
        state.statuses[message_id] = MessageStatus(
            message_id=message_id,
            status="queued",
            text=cleaned,
            audio_file=None,
            error=None,
            completed_at=None,
        )

    item = WorkItem(message_id=message_id, text=cleaned, voice=voice, audio=concurrent.futures.Future())
    state.work_queue.put(item)

    logger.debug(
        "POST /say request:\n%s",
        json.dumps({"text": body.text, "voice": voice, "message_id": message_id}, indent=2),
    )

    # Respond as soon as the WAV is generated; speaker playback continues in the background.
    try:
        audio = item.audio.result(timeout=state.runtime.timeout_seconds)
    except concurrent.futures.TimeoutError as error:
        raise HTTPException(
            status_code=504,
            detail=f"Timed out after {state.runtime.timeout_seconds}s waiting for audio generation",
        ) from error
    except Exception as error:
        raise HTTPException(status_code=500, detail=str(error)) from error

    return Response(
        content=audio,
        media_type="audio/wav",
        headers={"Content-Disposition": f'attachment; filename="{message_id}.wav"'},
    )


@router.get("/status/{message_id}")
def status(request: Request, message_id: str) -> StatusResponse:
    """Return the status of a queued, generating, playing, completed, or failed message."""
    state: ServerState = request.app.state.server
    state.evict_expired()

    with state.status_lock:
        message_status = state.statuses.get(message_id)

    if message_status is None:
        raise HTTPException(status_code=404, detail=f"Unknown message ID: {message_id}")

    return StatusResponse(
        message_id=message_status.message_id,
        status=message_status.status,
        text=message_status.text,
        audio_file=message_status.audio_file,
        error=message_status.error,
    )


def _fail_item(state: ServerState, item: WorkItem, error: str) -> None:
    """Mark one queued item as failed and release its waiting request."""
    with state.status_lock:
        message_status = state.statuses.get(item.message_id)
        if message_status is not None:
            message_status.status = "error"
            message_status.error = error
            message_status.completed_at = time.time()
    if not item.audio.done():
        item.audio.set_exception(RuntimeError(error))


def _start_playback(
    state: ServerState,
    player: AudioPlayer,
    work_item: WorkItem,
    generated: tuple[Path, Path | None, bool],
) -> None:
    """Queue a generated WAV on the player, which plays jobs in submission order."""
    wav_path, reported_path, delete_after_playback = generated

    def on_complete(output_path: Path | None) -> None:
        with state.status_lock:
            message_status = state.statuses[work_item.message_id]
            message_status.status = "completed"
            message_status.audio_file = str(output_path) if output_path is not None else None
            message_status.completed_at = time.time()
        logger.debug("Playback completed for %s -> %s", work_item.message_id, output_path)

    def on_error(error: Exception) -> None:
        logger.error("Playback failed for %s: %s", work_item.message_id, error)
        with state.status_lock:
            message_status = state.statuses[work_item.message_id]
            message_status.status = "error"
            message_status.error = str(error)
            message_status.completed_at = time.time()

    with state.status_lock:
        state.statuses[work_item.message_id].status = "playing"

    player.submit(
        PlaybackJob(
            wav_path=wav_path,
            reported_path=reported_path,
            delete_after_playback=delete_after_playback,
            on_complete=on_complete,
            on_error=on_error,
        )
    )


def _generate_item(state: ServerState, item: WorkItem) -> tuple[Path, Path | None, bool] | None:
    """Generate a WAV for one work item, hand its bytes to the request, and return playback metadata."""
    output_path = make_output_path(state.output_dir)
    reported_path = output_path if state.save_wav else None
    delete_after_playback = not state.save_wav

    with state.status_lock:
        state.statuses[item.message_id].status = "generating"

    try:
        generated_path = generate_wav(state.runtime, item.text, item.voice, output_path)
    except (FileExistsError, RuntimeError, TimeoutError, ValueError) as error:
        logger.error("Kokoro generation failed for %s: %s", item.message_id, error)
        _fail_item(state, item, str(error))
        if delete_after_playback and output_path.exists():
            output_path.unlink()
        return None

    # Read before playback is queued: playback deletes the file when save_wav is false.
    item.audio.set_result(generated_path.read_bytes())
    return generated_path, reported_path, delete_after_playback


def server_audio_worker(state: ServerState) -> None:
    """Background worker that generates Kokoro WAVs and queues them for sequential playback."""
    player = AudioPlayer(state.sample_rate, state.lead_silence_ms)

    try:
        while True:
            item = state.work_queue.get()
            if item is None:
                break

            try:
                generated = _generate_item(state, item)
                if generated is not None:
                    _start_playback(state, player, item, generated)
            except Exception as error:
                logger.error("Audio worker caught unexpected error: %s", error, exc_info=True)
                _fail_item(state, item, f"unexpected worker error: {error}")
            finally:
                state.work_queue.task_done()
    finally:
        player.close()


@dataclasses.dataclass(frozen=True)
class _ServerConfig:
    """Parsed server configuration from config.yaml."""

    runtime: KokoroRuntimeConfig
    output_dir: Path
    sample_rate: int
    default_voice: str
    simplify_punctuation_enabled: bool
    save_wav: bool
    lead_silence_ms: int
    host: str
    port: int


def _require(config: dict[str, object], key: str) -> object:
    """Fetch a required config key or raise a clear error."""
    if key not in config:
        raise ValueError(f"Missing required key '{key}' in config.yaml")
    value = config[key]
    if value is None:
        raise ValueError(f"Missing required key '{key}' in config.yaml")
    return value


def _require_str(config: dict[str, object], key: str) -> str:
    """Fetch a required string config key."""
    value = _require(config, key)
    if not isinstance(value, str):
        raise ValueError(f"'{key}' in config.yaml must be a string")
    return value


def _require_bool(config: dict[str, object], key: str) -> bool:
    """Fetch a required boolean config key."""
    value = _require(config, key)
    if not isinstance(value, bool):
        raise ValueError(f"'{key}' in config.yaml must be a boolean")
    return value


def _require_int(config: dict[str, object], key: str) -> int:
    """Fetch a required integer config key."""
    value = _require(config, key)
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError(f"'{key}' in config.yaml must be an integer")
    return value


def _parse_server_config() -> _ServerConfig:
    """Load and validate server settings from config.yaml."""
    config = load_config()
    runtime = KokoroRuntimeConfig(
        tts_cli=Path(_require_str(config, "tts_cli")),
        phonemize_cli=Path(_require_str(config, "phonemize_cli")),
        model_path=Path(_require_str(config, "model")),
        n_threads=_require_int(config, "n_threads"),
        timeout_seconds=_require_int(config, "timeout_seconds"),
    )
    return _ServerConfig(
        runtime=runtime,
        output_dir=Path(_require_str(config, "output_dir")),
        sample_rate=_require_int(config, "sample_rate"),
        default_voice=_require_str(config, "default_voice"),
        simplify_punctuation_enabled=_require_bool(config, "simplify_punctuation"),
        save_wav=_require_bool(config, "save_wav"),
        lead_silence_ms=_require_int(config, "lead_silence_ms"),
        host=_require_str(config, "host"),
        port=_require_int(config, "port"),
    )


def _build_server_state(config: _ServerConfig) -> ServerState:
    """Build validated runtime state for the FastAPI app."""
    validate_runtime_config(config.runtime)
    voices = kokoro_voices()
    if config.default_voice not in voices:
        raise ValueError(f"default_voice '{config.default_voice}' not found. Available: {', '.join(voices)}")
    if config.sample_rate <= 0:
        raise ValueError(f"sample_rate must be > 0, got {config.sample_rate}")
    if config.lead_silence_ms < 0:
        raise ValueError(f"lead_silence_ms must be >= 0, got {config.lead_silence_ms}")

    return ServerState(
        runtime=config.runtime,
        output_dir=config.output_dir,
        voices=voices,
        default_voice=config.default_voice,
        sample_rate=config.sample_rate,
        lead_silence_ms=config.lead_silence_ms,
        simplify_punctuation_enabled=config.simplify_punctuation_enabled,
        save_wav=config.save_wav,
    )


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None]:
    """Start the server worker and shut it down cleanly with the app."""
    state = _build_server_state(_parse_server_config())
    app.state.server = state
    load_tts_model(state.runtime)
    worker = threading.Thread(target=server_audio_worker, args=(state,), daemon=True)
    worker.start()

    yield

    state.work_queue.put(None)
    worker.join(timeout=10)
    if worker.is_alive():
        raise RuntimeError("Kokoro audio worker did not shut down within 10 seconds")
    unload_tts_model(state.runtime)


app = FastAPI(lifespan=lifespan)
app.include_router(router)


def run_server() -> None:
    """Run the configured FastAPI app with uvicorn."""
    config = _parse_server_config()
    logging.basicConfig(
        level=logging.DEBUG,
        format="%(asctime)s | %(levelname)s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    import uvicorn

    uvicorn.run("low_latency_tts_service_mcp.server:app", host=config.host, port=config.port, log_level="debug")


if __name__ == "__main__":
    run_server()
