#!/usr/bin/env bash
#
# Clone, patch and build the TTS.cpp tts-cli and phonemize binaries.
#
# vendor/ is gitignored, so the build output is a local artifact. Everything
# needed to reproduce it lives in this repository: the upstream commit pinned
# below and patches/tts-cpp.patch.
#
# Re-running is safe and cheap: when patches/tts-cpp.patch changed, the checkout
# is reset to the pinned commit and the new patch is applied; cmake then
# rebuilds only what changed.
#
# To move to a newer upstream TTS.cpp: bump TTS_CPP_COMMIT, delete vendor/,
# re-run. If the patch no longer applies, re-create it with:
#   git -C vendor/TTS.cpp diff > patches/tts-cpp.patch
set -euo pipefail

TTS_CPP_REPO="https://github.com/mmwillet/TTS.cpp.git"
TTS_CPP_COMMIT="c04c77ab7575adf48c8af5a16e3bea179cba7dbb"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKOUT="$ROOT/vendor/TTS.cpp"
PATCH="$ROOT/patches/tts-cpp.patch"
TTS_CLI="$CHECKOUT/build/bin/tts-cli"
PHONEMIZE="$CHECKOUT/build/bin/phonemize"

for tool in git cmake; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf "\033[0;31m✗ Error: %s is not installed\033[0m\n" "$tool"
        exit 1
    fi
done

if [ ! -f "$PATCH" ]; then
    printf "\033[0;31m✗ Error: patch not found: %s\033[0m\n" "$PATCH"
    exit 1
fi

if [ ! -d "$CHECKOUT/.git" ]; then
    printf "\033[0;34mCloning TTS.cpp at %s\033[0m\n" "$TTS_CPP_COMMIT"
    rm -rf "$CHECKOUT"
    mkdir -p "$(dirname "$CHECKOUT")"
    git clone "$TTS_CPP_REPO" "$CHECKOUT"
    git -C "$CHECKOUT" checkout --quiet "$TTS_CPP_COMMIT"
    git -C "$CHECKOUT" submodule update --init --recursive
fi

# Apply the patch only when it is not already applied. A checkout carrying an
# older version of the patch is reset to the pinned commit first.
if git -C "$CHECKOUT" apply --reverse --check "$PATCH" 2>/dev/null; then
    printf "\033[0;32m✓ Patch already applied\033[0m\n"
else
    if ! git -C "$CHECKOUT" diff --quiet; then
        printf "\033[0;33m⚠ Checkout carries a different patch, resetting to %s\033[0m\n" "$TTS_CPP_COMMIT"
        git -C "$CHECKOUT" reset --quiet --hard "$TTS_CPP_COMMIT"
    fi
    printf "\033[0;34mApplying patches/tts-cpp.patch\033[0m\n"
    git -C "$CHECKOUT" apply "$PATCH"
fi

# The ggml backends are pinned off so every machine builds the same CPU binary.
# cmake would otherwise default Accelerate, BLAS and Metal on under macOS, and a
# BLAS matmul backend changes float rounding, so the generated audio would differ
# from the output this project was tuned against. tts-cli runs on CPU regardless
# unless it is passed --use-metal, which this project never does.
#
# SDL2 is off because it only powers tts-cli's --play flag; playback happens in
# Python via sounddevice. Left on, cmake fetches SDL2 from source, which needs
# the X11/ALSA development headers on Linux.
printf "\033[0;34mBuilding tts-cli and phonemize (Release, CPU)\033[0m\n"
cmake -S "$CHECKOUT" -B "$CHECKOUT/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DTTS_CLI_SDL=OFF \
    -DGGML_ACCELERATE=OFF \
    -DGGML_BLAS=OFF \
    -DGGML_METAL=OFF > /dev/null
cmake --build "$CHECKOUT/build" --target tts-cli phonemize -j "$(sysctl -n hw.ncpu 2>/dev/null || nproc)" > /dev/null

if [ ! -f "$TTS_CLI" ] || [ ! -f "$PHONEMIZE" ]; then
    printf "\033[0;31m✗ Error: build finished but the binaries are missing\033[0m\n"
    exit 1
fi

printf "\033[0;32m✓ TTS.cpp binaries built\033[0m\n"
