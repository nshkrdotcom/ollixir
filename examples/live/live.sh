#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."
version=0.40.18
state="$PWD/tmp/ollixir-live"
bundle="$state/ollama-$version"
ollama="$bundle/bin/ollama"
host=127.0.0.1:41434
url="http://$host"

die() { printf '%s\n' "$*" >&2; exit 1; }
require() { command -v "$1" >/dev/null || die "Missing command: $1. See guides/live-validation.md."; }

export LIVE_TEXT="${LIVE_TEXT:-qwen3:4b}"
export LIVE_EMBED="${LIVE_EMBED:-nomic-embed-text:latest}"
export LIVE_VISION="${LIVE_VISION:-gemma3:4b}"
export LIVE_FIM="${LIVE_FIM:-codegemma:2b}"
export LIVE_DECISION="${LIVE_DECISION:-nimble:latest}"
export LIVE_DECISION_IMAGE="${LIVE_DECISION_IMAGE:-clef-flash:latest}"
export LIVE_MULTIMODAL="${LIVE_MULTIMODAL:-embeddinggemma-2:740m-q8_0}"
export LIVE_ASR="${LIVE_ASR:-lfm3-audio:2b-q4_K_M}"
export LIVE_SPEECH="${LIVE_SPEECH:-phonon:en}"
export LIVE_SPEECH_FR="${LIVE_SPEECH_FR:-phonon:fr}"
export OLLIXIR_RELEASE_LIVE_HOST="$url"

server_version() { curl -fsS --max-time 5 "$url/api/version"; }
require_server() {
  require curl
  local response pid
  [[ -r "$state/server.pid" ]] || die "Start the isolated server with $0 serve."
  read -r pid < "$state/server.pid"
  [[ $pid =~ ^[0-9]+$ && "/proc/$pid/exe" -ef "$ollama" ]] ||
    die "The isolated server is not running. Start it with $0 serve."
  grep -zFxq "OLLAMA_MODELS=$state/models" "/proc/$pid/environ" ||
    die 'The running server does not use the isolated model store.'
  response=$(server_version) || die "Start the isolated server with $0 serve."
  [[ $response == "{\"version\":\"$version\"}" ]] ||
    die "Expected Ollama $version at $url, got $response."
}
run_cli() { OLLAMA_HOST="$host" "$ollama" "$@"; }

case "${1:-help}" in
  doctor)
    printf 'Pinned release server: %s on %s\n' "$version" "$host"
    if command -v ollama >/dev/null; then printf 'Installed CLI: %s\n' "$(command -v ollama)"; fi
    if command -v nvidia-smi >/dev/null; then
      nvidia-smi --query-gpu=name,memory.total,memory.free,driver_version --format=csv || true
    fi
    for port in 11434 41434; do
      printf 'Server on %s: ' "$port"
      curl -fsS --max-time 3 "http://127.0.0.1:$port/api/version" || printf 'unavailable'
      printf '\n'
    done
    df -h .
    ;;
  setup)
    [[ $(uname -s)/$(uname -m) == Linux/x86_64 ]] || die 'Automatic setup targets Linux x86-64.'
    for cmd in curl sha256sum tar zstd; do require "$cmd"; done
    if [[ -x "$ollama" ]]; then printf 'Bundle already present at %s\n' "$bundle"; exit 0; fi
    [[ ! -e "$bundle" ]] || die "Move the incomplete bundle at $bundle before retrying."
    mkdir -p "$state"
    staging=$(mktemp -d "$state/setup.XXXXXXXX")
    trap 'rm -rf -- "$staging"' EXIT
    asset=ollama-linux-amd64.tar.zst
    curl --fail --location --retry 2 -o "$staging/$asset" \
      "https://github.com/ollama/ollama/releases/download/v$version/$asset"
    (cd "$staging" && printf '%s  %s\n' \
      b82649006cb5b54ed1237fa2d1a26a7f939a4fd03150033759acbff7ff315adf "$asset" | sha256sum -c)
    mkdir "$staging/bundle"
    tar --zstd -xf "$staging/$asset" -C "$staging/bundle"
    [[ -x "$staging/bundle/bin/ollama" ]] || die 'Expected bin/ollama in the release archive.'
    mv -T "$staging/bundle" "$bundle"
    ;;
  serve|serve-cloud)
    require curl
    if server_version >/dev/null 2>&1; then die "$host is already serving Ollama."; fi
    [[ -x "$ollama" ]] || die "Run $0 setup first."
    # Keep account keys and model files separate from the installed server.
    mkdir -p "$state/home" "$state/models"
    export HOME="$state/home" OLLAMA_MODELS="$state/models" OLLAMA_HOST="$host"
    export OLLAMA_NUM_PARALLEL=1 OLLAMA_MAX_LOADED_MODELS=1 OLLAMA_CONTEXT_LENGTH=4096
    unset OLLAMA_API_KEY
    if [[ $1 == serve ]]; then export OLLAMA_NO_CLOUD=1; else export OLLAMA_NO_CLOUD=0; fi
    printf '%s\n' "$$" > "$state/server.pid"
    exec "$ollama" serve
    ;;
  models)
    require_server
    [[ -x "$ollama" ]] || die "Run $0 setup first."
    for model in "$LIVE_TEXT" "$LIVE_EMBED" "$LIVE_VISION" "$LIVE_FIM" "$LIVE_DECISION" \
      "$LIVE_DECISION_IMAGE" "$LIVE_MULTIMODAL" "$LIVE_ASR" "$LIVE_SPEECH" "$LIVE_SPEECH_FR"; do
      if ! run_cli show "$model" >/dev/null 2>&1; then run_cli pull "$model"; fi
    done
    ;;
  signin)
    require_server
    [[ -x "$ollama" ]] || die "Run $0 setup first."
    HOME="$state/home" run_cli signin
    ;;
  mock)
    require mix
    exec env -u OLLAMA_HOST -u OLLAMA_API_KEY mix test
    ;;
  check|hf|cloud|registry|push)
    require mix
    require_server
    export LIVE_OUTPUT="$state/results"
    if [[ $1 != cloud ]]; then unset OLLAMA_API_KEY; fi
    mkdir -p "$LIVE_OUTPUT"
    log=$(mktemp "$LIVE_OUTPUT/$1.XXXXXXXX")
    printf 'Log: %s\n' "$log"
    mix run examples/live/live.exs -- "$1" 2>&1 | tee "$log"
    ;;
  help|-h|--help)
    cat <<'HELP'
Ollixir 0.2.0 live validation (see guides/live-validation.md)
  doctor       Show server versions, GPU/VRAM and available disk
  setup        Download and verify the isolated Ollama 0.40.18 Linux bundle
  serve        Start the isolated server in the foreground with cloud disabled
  models       Download the local fixtures that are missing
  mock         Run the standard ExUnit suite
  check        Run all local live checks and summarize failures
  serve-cloud  Start the same isolated server with cloud enabled
  signin       Sign in to that isolated server
  hf           Pull and exercise one small Hugging Face fixture
  registry     Exercise Ollixir pull against the Ollama registry
  cloud        Check signed-in account status and local/hosted web
  push         Push only to an explicitly selected disposable registry tag
HELP
    ;;
  *) die "Unknown command: $1. Run $0 help." ;;
esac
