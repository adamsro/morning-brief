#!/bin/bash
# morning-brief — Run AI prompts on a schedule, get daily reports.
# https://github.com/mimicscribe/morning-brief

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${MORNING_BRIEF_CONFIG:-$SCRIPT_DIR/config.sh}"
STATE_DIR="${MORNING_BRIEF_STATE:-$HOME/.morning-brief}"
REPORTS_DIR="${MORNING_BRIEF_REPORTS:-$SCRIPT_DIR/reports}"

# --- Load config ---
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Error: Config file not found at $CONFIG_FILE" >&2
  echo "Copy config.example.sh to config.sh and customize it." >&2
  exit 1
fi
source "$CONFIG_FILE"

# --- Defaults ---
BACKEND="${BACKEND:-claude}"
PROMPT_FILE="${PROMPT_FILE:-$SCRIPT_DIR/prompts/competitor-analysis.md}"
REPORT_PREFIX="${REPORT_PREFIX:-report}"
NOTIFY="${NOTIFY:-true}"
ONCE_PER_DAY="${ONCE_PER_DAY:-true}"

# --- Functions ---

log() {
  echo "[morning-brief] $(date '+%Y-%m-%d %H:%M:%S') $*"
}

notify() {
  local title="$1"
  local message="$2"
  if [[ "$NOTIFY" == "true" ]] && command -v osascript &>/dev/null; then
    osascript -e "display notification \"$message\" with title \"$title\""
  fi
}

check_already_ran_today() {
  if [[ "$ONCE_PER_DAY" != "true" ]]; then
    return 1
  fi
  local today
  today=$(date '+%Y-%m-%d')
  local stamp_file="$STATE_DIR/last-run"
  if [[ -f "$stamp_file" ]] && [[ "$(cat "$stamp_file")" == "$today" ]]; then
    return 0
  fi
  return 1
}

mark_ran_today() {
  mkdir -p "$STATE_DIR"
  date '+%Y-%m-%d' > "$STATE_DIR/last-run"
}

resolve_prompt() {
  if [[ ! -f "$PROMPT_FILE" ]]; then
    echo "Error: Prompt file not found at $PROMPT_FILE" >&2
    exit 1
  fi

  local prompt
  prompt=$(cat "$PROMPT_FILE")

  # Substitute {{DATE}} and {{VARIABLES}} from config
  prompt="${prompt//\{\{DATE\}\}/$(date '+%A, %B %d, %Y')}"
  if [[ -n "${PRODUCT_NAME:-}" ]]; then
    prompt="${prompt//\{\{PRODUCT_NAME\}\}/$PRODUCT_NAME}"
  fi
  if [[ -n "${COMPETITORS:-}" ]]; then
    prompt="${prompt//\{\{COMPETITORS\}\}/$COMPETITORS}"
  fi
  if [[ -n "${PRODUCT_DESCRIPTION:-}" ]]; then
    prompt="${prompt//\{\{PRODUCT_DESCRIPTION\}\}/$PRODUCT_DESCRIPTION}"
  fi
  if [[ -n "${FOCUS_AREAS:-}" ]]; then
    prompt="${prompt//\{\{FOCUS_AREAS\}\}/$FOCUS_AREAS}"
  fi

  echo "$prompt"
}

run_claude() {
  local prompt="$1"
  local output_file="$2"

  if ! command -v claude &>/dev/null; then
    echo "Error: 'claude' CLI not found. Install Claude Code: https://docs.anthropic.com/en/docs/claude-code" >&2
    exit 1
  fi

  log "Running prompt via Claude Code..."
  claude --print --allowedTools "WebSearch,WebFetch" -p "$prompt" > "$output_file" 2>/dev/null
}

run_backend() {
  local prompt="$1"
  local output_file="$2"

  case "$BACKEND" in
    claude)
      run_claude "$prompt" "$output_file"
      ;;
    *)
      echo "Error: Unknown backend '$BACKEND'. Supported: claude" >&2
      exit 1
      ;;
  esac
}

# --- Main ---

main() {
  # Parse args
  local force=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force|-f)
        force=true
        shift
        ;;
      --prompt|-p)
        PROMPT_FILE="$2"
        shift 2
        ;;
      --backend|-b)
        BACKEND="$2"
        shift 2
        ;;
      --config|-c)
        CONFIG_FILE="$2"
        source "$CONFIG_FILE"
        shift 2
        ;;
      --help|-h)
        echo "Usage: morning-brief [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  -f, --force       Run even if already ran today"
        echo "  -p, --prompt      Path to prompt template file"
        echo "  -b, --backend     AI backend (claude)"
        echo "  -c, --config      Path to config file"
        echo "  -h, --help        Show this help"
        exit 0
        ;;
      *)
        echo "Unknown option: $1" >&2
        exit 1
        ;;
    esac
  done

  # Once-per-day guard
  if [[ "$force" == "false" ]] && check_already_ran_today; then
    log "Already ran today. Use --force to run again."
    exit 0
  fi

  # Setup
  mkdir -p "$REPORTS_DIR" "$STATE_DIR"

  local today
  today=$(date '+%Y-%m-%d')
  local output_file="$REPORTS_DIR/${REPORT_PREFIX}-${today}.md"

  # Resolve prompt template
  local prompt
  prompt=$(resolve_prompt)

  log "Backend: $BACKEND"
  log "Prompt: $PROMPT_FILE"
  log "Output: $output_file"

  notify "Morning Brief" "Generating your daily report..."

  # Run
  local start_time
  start_time=$(date +%s)

  if run_backend "$prompt" "$output_file"; then
    local elapsed=$(( $(date +%s) - start_time ))
    mark_ran_today
    log "Report saved to $output_file (${elapsed}s)"
    notify "Morning Brief" "Your daily report is ready."

    # Open report if configured
    if [[ "${OPEN_AFTER:-false}" == "true" ]]; then
      open "$output_file"
    fi
  else
    log "Error: Report generation failed."
    notify "Morning Brief" "Report generation failed. Check logs."
    exit 1
  fi
}

main "$@"
