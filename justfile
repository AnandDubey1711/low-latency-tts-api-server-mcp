# =============================================================================
# Justfile Rules (follow these when editing justfile):
#
# 1. Use printf (not echo) to print colors — some terminals won't render
#    colors with echo.
#
# 2. Always add an empty `@echo ""` line before and after each target's
#    command block.
#
# 3. Always add new targets to the help section and update it when targets
#    are added, modified or removed.
#
# 4. Target ordering in help (and in this file) matters:
#    - Setup targets first (init, setup, install, etc.)
#    - Start/stop/run targets next
#    - Code generation / data tooling targets next
#    - Checks, linting, and tests next (ordered fastest to slowest)
#    Group related targets together and separate groups with an empty
#    `@echo ""` line in the help output.
#
# 5. Composite targets (e.g. ci) that call multiple sub-targets must fail
#    fast: exit 1 on the first error. Never skip over errors or warnings.
#    Use `set -e` or `&&` chaining to ensure immediate abort with the
#    appropriate error message.
#
# 6. Every target must end with a clear short status message:
#    - On success: green (\033[32m) message confirming completion.
#      E.g. printf "\033[32m✓ init completed successfully\033[0m\n"
#    - On failure: red (\033[31m) message indicating what failed, then exit 1.
#      E.g. printf "\033[31m✗ ci failed: tests exited with errors\033[0m\n"
# 7. Targets must be shown in groups separated by empty newlines in the help section.
#    - init/destroy/clean/help on top, ci and other tests on the bottom, between other groups
# =============================================================================

# Default recipe: show available commands
_default:
    @just help

# Show help information
help:
    @echo ""
    @clear
    @echo ""
    @printf "\033[0;34m=== low-latency-tts-service-mcp ===\033[0m\n"
    @echo ""
    @printf "\033[0;33mSetup & Lifecycle:\033[0m\n"
    @printf "  %-40s %s\n" "init" "Initialize the development environment"
    @printf "  %-40s %s\n" "build-tts" "Clone, patch and build the TTS.cpp binaries"
    @printf "  %-40s %s\n" "download" "Download the Kokoro TTS model"
    @printf "  %-40s %s\n" "destroy" "Destroy the virtual environment"
    @printf "  %-40s %s\n" "check" "Check prerequisites"
    @printf "  %-40s %s\n" "help" "Show this help message"
    @echo ""
    @printf "\033[0;33mRun:\033[0m\n"
    @printf "  %-40s %s\n" "chat" "Run the interactive chat"
    @printf "  %-40s %s\n" "convert <voice> <input> <output>" "Convert a text file into an MP3 file"
    @printf "  %-40s %s\n" "start" "Start the FastAPI TTS server"
    @printf "  %-40s %s\n" "stop" "Stop the FastAPI TTS server"
    @printf "  %-40s %s\n" "status" "Check if the TTS server is running"
    @printf "  %-40s %s\n" "on-demand" "Speak <voice> <text> via the API, auto-starting the server"
    @printf "  %-40s %s\n" "mcp-install" "Install MCP server Node dependencies"
    @printf "  %-40s %s\n" "mcp-start" "Start the Kokoro MCP stdio relay"
    @printf "  %-40s %s\n" "mcp-typecheck" "Type-check the Kokoro MCP TypeScript relay"
    @echo ""
    @printf "\033[0;33mCode Quality:\033[0m\n"
    @printf "  %-40s %s\n" "code-format" "Auto-fix code style and formatting"
    @printf "  %-40s %s\n" "code-style" "Check code style and formatting (read-only)"
    @printf "  %-40s %s\n" "code-typecheck" "Run static type checking with mypy"
    @printf "  %-40s %s\n" "code-lspchecks" "Run strict type checking with Pyright (LSP-based)"
    @printf "  %-40s %s\n" "code-security" "Run security checks with bandit"
    @printf "  %-40s %s\n" "code-deptry" "Check dependency hygiene with deptry"
    @printf "  %-40s %s\n" "code-spell" "Check spelling in code and documentation"
    @printf "  %-40s %s\n" "code-semgrep" "Run Semgrep static analysis"
    @printf "  %-40s %s\n" "code-audit" "Scan dependencies for known vulnerabilities"
    @printf "  %-40s %s\n" "code-architecture" "Run architecture import rule tests"
    @printf "  %-40s %s\n" "code-stats" "Generate code statistics with pygount"
    @echo ""
    @printf "\033[0;33mCI & Testing:\033[0m\n"
    @printf "  %-40s %s\n" "test" "Run unit tests only (fast)"
    @printf "  %-40s %s\n" "test-coverage" "Run unit tests with coverage report"
    @printf "  %-40s %s\n" "ci" "Run ALL validation checks (verbose)"
    @printf "  %-40s %s\n" "ci-quiet" "Run ALL validation checks silently"
    @echo ""

# Initialize the development environment
init: check build-tts
    @echo ""
    @printf "\033[0;34m=== Initializing Development Environment ===\033[0m\n"
    @mkdir -p reports/coverage
    @mkdir -p reports/security
    @mkdir -p reports/pyright
    @mkdir -p reports/deptry
    @printf "Installing Python dependencies...\n"
    @uv sync --all-extras
    @if [ ! -f data/models/Kokoro_no_espeak.gguf ]; then \
        if [ -t 0 ]; then \
            printf "\033[0;33m⚠ No Kokoro model found. Starting download...\033[0m\n"; \
            echo ""; \
            bash scripts/download-model.sh; \
        else \
            printf "\033[0;33m⚠ No Kokoro model found. Run 'just download' to fetch it.\033[0m\n"; \
        fi; \
    fi
    @printf "\033[0;32m✓ Development environment ready\033[0m\n"
    @echo ""

# Clone, patch and build the TTS.cpp binaries
build-tts:
    @echo ""
    @printf "\033[0;34m=== Building TTS.cpp Binaries ===\033[0m\n"
    @bash scripts/build-tts.sh
    @echo ""

# Download the Kokoro TTS model
download:
    @echo ""
    @printf "\033[0;34m=== Downloading Kokoro TTS Model ===\033[0m\n"
    @bash scripts/download-model.sh
    @echo ""
    @printf "\033[0;32m✓ Model download completed\033[0m\n"
    @echo ""

# Destroy the virtual environment
destroy:
    @echo ""
    @printf "\033[0;34m=== Destroying Virtual Environment ===\033[0m\n"
    @rm -rf .venv
    @printf "\033[0;32m✓ Virtual environment removed\033[0m\n"
    @echo ""

# Check prerequisites
check:
    @echo ""
    @if ! command -v python3 >/dev/null 2>&1; then \
        printf "\033[0;31m✗ Error: python3 is not installed\033[0m\n"; \
        printf "  Install Python 3.12+ from: https://python.org/downloads/\n"; \
        echo ""; \
        exit 1; \
    fi
    @printf "\033[0;32m✓ python3 is installed\033[0m\n"
    @if ! command -v uv >/dev/null 2>&1; then \
        printf "\033[0;31m✗ Error: uv is not installed\033[0m\n"; \
        printf "  Install with: curl -LsSf https://astral.sh/uv/install.sh | sh\n"; \
        echo ""; \
        exit 1; \
    fi
    @printf "\033[0;32m✓ uv is installed\033[0m\n"
    @if ! command -v git >/dev/null 2>&1; then \
        printf "\033[0;31m✗ Error: git is not installed\033[0m\n"; \
        printf "  git is required to fetch and patch TTS.cpp\n"; \
        echo ""; \
        exit 1; \
    fi
    @printf "\033[0;32m✓ git is installed\033[0m\n"
    @if ! command -v cmake >/dev/null 2>&1; then \
        printf "\033[0;31m✗ Error: cmake is not installed\033[0m\n"; \
        printf "  Install with: brew install cmake\n"; \
        echo ""; \
        exit 1; \
    fi
    @printf "\033[0;32m✓ cmake is installed\033[0m\n"
    @if ! command -v ffmpeg >/dev/null 2>&1; then \
        printf "\033[0;31m✗ Error: ffmpeg is not installed\033[0m\n"; \
        printf "  Install with: brew install ffmpeg\n"; \
        echo ""; \
        exit 1; \
    fi
    @printf "\033[0;32m✓ ffmpeg is installed\033[0m\n"
    @if ! uv run python -c "import sounddevice" >/dev/null 2>&1; then \
        printf "\033[0;31m✗ Error: PortAudio library not found (needed by sounddevice)\033[0m\n"; \
        printf "  Install with: sudo apt install libportaudio2 (Linux) or brew install portaudio (macOS)\n"; \
        echo ""; \
        exit 1; \
    fi
    @printf "\033[0;32m✓ PortAudio is installed\033[0m\n"
    @echo ""

# Run the interactive chat
chat:
    @echo ""
    @printf "\033[0;34m=== Running Interactive Chat ===\033[0m\n"
    @uv run -m src.main
    @echo ""

# Compatibility alias required by this repo's agent rules
run: chat

# Convert a text file into an MP3 file
convert voice input output:
    #!/usr/bin/env bash
    echo ""
    printf "\033[0;34m=== Converting Text File to MP3 ===\033[0m\n"
    if uv run -m src.main --voice {{quote(voice)}} --input-file {{quote(input)}} --output {{quote(output)}}; then
        printf "\033[0;32m✓ convert completed successfully\033[0m\n"
    else
        printf "\033[0;31m✗ convert failed\033[0m\n"
        echo ""
        exit 1
    fi
    echo ""

# Start the FastAPI TTS server
start:
    @echo ""
    @printf "\033[0;34m=== Starting TTS Server ===\033[0m\n"
    @uv run -m src.server
    @echo ""

# Stop the FastAPI TTS server
stop:
    @echo ""
    @printf "\033[0;34m=== Stopping TTS Server ===\033[0m\n"
    @if pkill -f "src.server"; then \
        printf "\033[0;32m✓ Server stopped\033[0m\n"; \
    else \
        printf "\033[0;31m✗ No running server found\033[0m\n"; \
        exit 1; \
    fi
    @echo ""

# Check if the FastAPI TTS server is running
status:
    #!/usr/bin/env bash
    echo ""
    PORT=$(uv run python3 -c "import yaml; print(yaml.safe_load(open('config.yaml'))['port'])")
    HOST=$(uv run python3 -c "import yaml; print(yaml.safe_load(open('config.yaml'))['host'])")
    CONNECT_HOST="$HOST"
    if [ "$CONNECT_HOST" = "0.0.0.0" ]; then
        CONNECT_HOST="127.0.0.1"
    fi
    if curl -s --max-time 2 "http://${CONNECT_HOST}:${PORT}/health" | grep -q '"ok"'; then
        printf "\033[0;32m✓ Server is running (http://%s:%s)\033[0m\n" "$CONNECT_HOST" "$PORT"
    else
        printf "\033[0;31m✗ Server is not running\033[0m\n"
        exit 1
    fi
    echo ""

# Speak text via the API, auto-starting the server in the background if down
on-demand voice text:
    #!/usr/bin/env bash
    set -e
    echo ""
    printf "\033[0;34m=== Speaking On Demand ===\033[0m\n"
    PORT=$(uv run python3 -c "import yaml; print(yaml.safe_load(open('config.yaml'))['port'])")
    HOST=$(uv run python3 -c "import yaml; print(yaml.safe_load(open('config.yaml'))['host'])")
    CONNECT_HOST="$HOST"
    if [ "$CONNECT_HOST" = "0.0.0.0" ]; then
        CONNECT_HOST="127.0.0.1"
    fi
    BASE_URL="http://${CONNECT_HOST}:${PORT}"
    if ! curl -s --max-time 2 "$BASE_URL/health" | grep -q '"ok"'; then
        printf "\033[0;33m⚠ Server not running — starting it in the background...\033[0m\n"
        nohup uv run -m src.server >/dev/null 2>&1 &
        WAITED=0
        until curl -s --max-time 2 "$BASE_URL/health" | grep -q '"ok"'; do
            if [ "$WAITED" -ge 60 ]; then
                printf "\033[0;31m✗ Server did not become healthy within 60s\033[0m\n"
                echo ""
                exit 1
            fi
            sleep 1
            WAITED=$((WAITED + 1))
        done
        printf "\033[0;32m✓ Server started (%s)\033[0m\n" "$BASE_URL"
    fi
    VOICE_ARG={{quote(voice)}}
    TEXT_ARG={{quote(text)}}
    PAYLOAD=$(uv run python3 -c "import json, sys; print(json.dumps({'text': sys.argv[1], 'voice': sys.argv[2]}))" "$TEXT_ARG" "$VOICE_ARG")
    curl -sS -f -X POST "$BASE_URL/say" -H "Content-Type: application/json" -d "$PAYLOAD" >/dev/null
    printf "\033[0;32m✓ Sent to TTS (voice: %s)\033[0m\n" "$VOICE_ARG"
    echo ""

# Install MCP server dependencies
mcp-install:
    #!/usr/bin/env bash
    set -euo pipefail
    echo ""
    printf "\033[0;34m=== Installing MCP Server Dependencies ===\033[0m\n"
    cd mcp
    npm install
    printf "\033[0;32m✓ MCP dependencies installed\033[0m\n"
    echo ""

# Start the MCP stdio relay
mcp-start:
    #!/usr/bin/env bash
    set -euo pipefail
    echo ""
    printf "\033[0;34m=== Starting Kokoro MCP Server ===\033[0m\n"
    cd mcp
    if npm start; then
        printf "\033[0;32m✓ mcp-start completed successfully\033[0m\n"
    else
        printf "\033[0;31m✗ mcp-start failed\033[0m\n"
        exit 1
    fi
    echo ""

# Type-check the MCP stdio relay
mcp-typecheck: mcp-install
    #!/usr/bin/env bash
    set -euo pipefail
    echo ""
    printf "\033[0;34m=== Type-checking Kokoro MCP Server ===\033[0m\n"
    cd mcp
    npm exec tsc -- --noEmit
    printf "\033[0;32m✓ MCP type checks passed\033[0m\n"
    echo ""

# Auto-fix code style and formatting
code-format:
    @echo ""
    @printf "\033[0;34m=== Formatting Code ===\033[0m\n"
    @uv run ruff check . --fix
    @echo ""
    @uv run ruff format .
    @echo ""
    @printf "\033[0;32m✓ Code formatted\033[0m\n"
    @echo ""

# Check code style and formatting (read-only)
code-style:
    @echo ""
    @printf "\033[0;34m=== Checking Code Style ===\033[0m\n"
    @uv run ruff check .
    @echo ""
    @uv run ruff format --check .
    @echo ""
    @printf "\033[0;32m✓ Style checks passed\033[0m\n"
    @echo ""

# Run static type checking with mypy
code-typecheck:
    @echo ""
    @printf "\033[0;34m=== Running Type Checks ===\033[0m\n"
    @uv run mypy
    @echo ""
    @printf "\033[0;32m✓ Type checks passed\033[0m\n"
    @echo ""

# Run strict type checking with Pyright (LSP-based)
code-lspchecks:
    @echo ""
    @printf "\033[0;34m=== Running Pyright Type Checks ===\033[0m\n"
    @uv run pyright --project pyrightconfig.json
    @echo ""
    @printf "\033[0;32m✓ Pyright checks passed\033[0m\n"
    @echo ""

# Run security checks with bandit
code-security:
    @echo ""
    @printf "\033[0;34m=== Running Security Checks ===\033[0m\n"
    @uv run bandit -c pyproject.toml --severity-level medium --confidence-level medium -r src
    @echo ""
    @printf "\033[0;32m✓ Security checks passed\033[0m\n"
    @echo ""

# Check dependency hygiene with deptry
code-deptry:
    @echo ""
    @printf "\033[0;34m=== Checking Dependencies ===\033[0m\n"
    @mkdir -p reports/deptry
    @uv run deptry src
    @echo ""
    @printf "\033[0;32m✓ Dependency checks passed\033[0m\n"
    @echo ""

# Check spelling in code and documentation
code-spell:
    @echo ""
    @printf "\033[0;34m=== Checking Spelling ===\033[0m\n"
    @uv run codespell src tests scripts *.md *.toml
    @echo ""
    @printf "\033[0;32m✓ Spelling checks passed\033[0m\n"
    @echo ""

# Run Semgrep static analysis
code-semgrep:
    @echo ""
    @printf "\033[0;34m=== Running Semgrep Static Analysis ===\033[0m\n"
    @uv run semgrep --config config/semgrep/ --error src scripts
    @echo ""
    @printf "\033[0;32m✓ Semgrep checks passed\033[0m\n"
    @echo ""

# Scan dependencies for known vulnerabilities
code-audit:
    @echo ""
    @printf "\033[0;34m=== Scanning Dependencies for Vulnerabilities ===\033[0m\n"
    @uv run pip-audit
    @echo ""
    @printf "\033[0;32m✓ No known vulnerabilities found\033[0m\n"
    @echo ""

# Run architecture import rule tests
code-architecture:
    @echo ""
    @printf "\033[0;34m=== Running Architecture Tests ===\033[0m\n"
    @uv run pytest tests/architecture/ -v --tb=long -x
    @echo ""
    @printf "\033[0;32m✓ Architecture checks passed\033[0m\n"
    @echo ""

# Generate code statistics with pygount
code-stats:
    @echo ""
    @printf "\033[0;34m=== Code Statistics ===\033[0m\n"
    @mkdir -p reports
    @uv run pygount src/ tests/ scripts/ *.md *.toml --suffix=py,md,txt,toml,yaml,yml --format=summary
    @echo ""
    @uv run pygount src/ tests/ scripts/ *.md *.toml --suffix=py,md,txt,toml,yaml,yml --format=summary > reports/code-stats.txt
    @printf "\033[0;32m✓ Report saved to reports/code-stats.txt\033[0m\n"
    @echo ""

# Run unit tests and integration tests
test: mcp-install
    @echo ""
    @printf "\033[0;34m=== Running Unit Tests ===\033[0m\n"
    @uv run pytest tests/ -v
    @printf "\033[0;32m✓ Tests passed\033[0m\n"
    @echo ""

# Run unit tests with coverage report and threshold check
test-coverage: init
    @echo ""
    @printf "\033[0;34m=== Running Unit Tests with Coverage ===\033[0m\n"
    @uv run pytest tests/ -v \
        --cov=src \
        --cov-report=html:reports/coverage/html \
        --cov-report=term \
        --cov-report=xml:reports/coverage/coverage.xml \
        --cov-fail-under=80
    @echo ""
    @printf "\033[0;32m✓ Coverage threshold met\033[0m\n"
    @printf "  HTML: reports/coverage/html/index.html\n"
    @echo ""

# Run ALL validation checks (verbose)
ci:
    #!/usr/bin/env bash
    set -e
    echo ""
    printf "\033[0;34m=== Running CI Checks ===\033[0m\n"
    echo ""
    just check
    just init
    just code-format
    just code-style
    just code-typecheck
    just code-security
    just code-deptry
    just code-spell
    just code-semgrep
    just code-audit
    just test
    just code-architecture
    just code-lspchecks
    just mcp-typecheck
    echo ""
    printf "\033[0;32m✓ All CI checks passed\033[0m\n"
    echo ""

# Run ALL validation checks silently (only show output on errors)
ci-quiet:
    #!/usr/bin/env bash
    set -e
    printf "\033[0;34m=== Running CI Checks (Quiet Mode) ===\033[0m\n"
    TMPFILE=$(mktemp)
    trap "rm -f $TMPFILE" EXIT

    just check > $TMPFILE 2>&1 || { printf "\033[0;31m✗ Check failed\033[0m\n"; cat $TMPFILE; exit 1; }
    printf "\033[0;32m✓ Check passed\033[0m\n"

    just init > $TMPFILE 2>&1 || { printf "\033[0;31m✗ Init failed\033[0m\n"; cat $TMPFILE; exit 1; }
    printf "\033[0;32m✓ Init passed\033[0m\n"

    just code-format > $TMPFILE 2>&1 || { printf "\033[0;31m✗ Code-format failed\033[0m\n"; cat $TMPFILE; exit 1; }
    printf "\033[0;32m✓ Code-format passed\033[0m\n"

    just code-style > $TMPFILE 2>&1 || { printf "\033[0;31m✗ Code-style failed\033[0m\n"; cat $TMPFILE; exit 1; }
    printf "\033[0;32m✓ Code-style passed\033[0m\n"

    just code-typecheck > $TMPFILE 2>&1 || { printf "\033[0;31m✗ Code-typecheck failed\033[0m\n"; cat $TMPFILE; exit 1; }
    printf "\033[0;32m✓ Code-typecheck passed\033[0m\n"

    just code-security > $TMPFILE 2>&1 || { printf "\033[0;31m✗ Code-security failed\033[0m\n"; cat $TMPFILE; exit 1; }
    printf "\033[0;32m✓ Code-security passed\033[0m\n"

    just code-deptry > $TMPFILE 2>&1 || { printf "\033[0;31m✗ Code-deptry failed\033[0m\n"; cat $TMPFILE; exit 1; }
    printf "\033[0;32m✓ Code-deptry passed\033[0m\n"

    just code-spell > $TMPFILE 2>&1 || { printf "\033[0;31m✗ Code-spell failed\033[0m\n"; cat $TMPFILE; exit 1; }
    printf "\033[0;32m✓ Code-spell passed\033[0m\n"

    just code-semgrep > $TMPFILE 2>&1 || { printf "\033[0;31m✗ Code-semgrep failed\033[0m\n"; cat $TMPFILE; exit 1; }
    printf "\033[0;32m✓ Code-semgrep passed\033[0m\n"

    just code-audit > $TMPFILE 2>&1 || { printf "\033[0;31m✗ Code-audit failed\033[0m\n"; cat $TMPFILE; exit 1; }
    printf "\033[0;32m✓ Code-audit passed\033[0m\n"

    just test > $TMPFILE 2>&1 || { printf "\033[0;31m✗ Test failed\033[0m\n"; cat $TMPFILE; exit 1; }
    printf "\033[0;32m✓ Test passed\033[0m\n"

    just code-architecture > $TMPFILE 2>&1 || { printf "\033[0;31m✗ Code-architecture failed\033[0m\n"; cat $TMPFILE; exit 1; }
    printf "\033[0;32m✓ Code-architecture passed\033[0m\n"

    just code-lspchecks > $TMPFILE 2>&1 || { printf "\033[0;31m✗ Code-lspchecks failed\033[0m\n"; cat $TMPFILE; exit 1; }
    printf "\033[0;32m✓ Code-lspchecks passed\033[0m\n"

    just mcp-typecheck > $TMPFILE 2>&1 || { printf "\033[0;31m✗ Mcp-typecheck failed\033[0m\n"; cat $TMPFILE; exit 1; }
    printf "\033[0;32m✓ Mcp-typecheck passed\033[0m\n"

    echo ""
    printf "\033[0;32m✓ All CI checks passed\033[0m\n"
    echo ""
