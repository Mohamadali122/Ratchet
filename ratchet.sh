#!/usr/bin/env bash
# ratchet.sh — Ratchet autonomous AI agent loop orchestrator
# Spawns repeated Claude Code iterations until all PRD stories pass or max iterations reached.

set -euo pipefail

TOOL="claude"
MAX_ITER=20
PROJECT_DIR="."

usage() {
  cat >&2 <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --tool TOOL         AI tool: claude (default) or codex
  --max-iter N        Max iterations before giving up (default: 20)
  --project-dir PATH  Project directory containing CLAUDE.md and .ratchet/ (default: .)
  --help              Show this help

Example:
  ./ratchet.sh --project-dir /srv/myapp --max-iter 15
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tool)        TOOL="$2";        shift 2 ;;
    --max-iter)    MAX_ITER="$2";    shift 2 ;;
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
    --help|-h)     usage ;;
    *)             echo "Unknown argument: $1" >&2; usage ;;
  esac
done

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
RATCHET_DIR="$PROJECT_DIR/.ratchet"
PRD="$RATCHET_DIR/prd.json"
PROGRESS="$RATCHET_DIR/progress.md"
LOGS_DIR="$PROJECT_DIR/logs"

# --- Validation ---
if [[ ! -f "$PRD" ]]; then
  echo "ERROR: $PRD not found. Run: ./ratchet_state.py init --name <name>" >&2
  exit 1
fi

if ! command -v "$TOOL" >/dev/null 2>&1; then
  echo "ERROR: '$TOOL' not found in PATH" >&2
  exit 1
fi

# Detect python (python3 on Linux/Mac, python on Windows)
PYTHON=""
if command -v python3 >/dev/null 2>&1; then
  PYTHON="python3"
elif command -v python >/dev/null 2>&1; then
  PYTHON="python"
else
  echo "ERROR: python3 or python not found in PATH" >&2
  exit 1
fi

mkdir -p "$LOGS_DIR"

# Count stories where passes == false
count_incomplete() {
  "$PYTHON" - "$PRD" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    prd = json.load(f)
print(len([s for s in prd.get("stories", []) if not s.get("passes", False)]))
PYEOF
}

# Build trigger prompt — prepend Authorization lines from company.md so the
# agent sees them immediately, before applying any independent security judgment.
COMPANY_MD="$RATCHET_DIR/company.md"
AUTH_PREFIX=""
if [[ -f "$COMPANY_MD" ]]; then
  AUTH_LINE="$(grep -E "^- Authorization:" "$COMPANY_MD" | head -1 | sed 's/^- //')"
  if [[ -n "$AUTH_LINE" ]]; then
    AUTH_PREFIX="${AUTH_LINE} "
  fi
fi

TRIGGER_PROMPT="${AUTH_PREFIX}You are running inside the Ratchet agent loop. \
Read CLAUDE.md for your full operating protocol, then \
work through the next incomplete story in .ratchet/prd.json."

iter=0
while [[ "$iter" -lt "$MAX_ITER" ]]; do
  iter=$((iter + 1))
  TIMESTAMP="$(date +%Y%m%dT%H%M%S)"
  LOG="$LOGS_DIR/ratchet-${TIMESTAMP}.log"

  incomplete="$(count_incomplete)"
  if [[ "$incomplete" -eq 0 ]]; then
    echo "=== All stories complete after $((iter - 1)) iteration(s). ==="
    exit 0
  fi

  echo "=== Iteration ${iter}/${MAX_ITER} | Incomplete stories: ${incomplete} ===" | tee -a "$LOG"
  echo "Log: $LOG"

  # Run the AI tool from within the project directory, streaming output to log
  set +e
  (
    cd "$PROJECT_DIR"
    "$TOOL" --dangerously-skip-permissions -p "$TRIGGER_PROMPT"
  ) 2>&1 | tee -a "$LOG"
  set -e

  # Inspect log for completion signals
  if grep -qE "^COMPLETE" "$LOG"; then
    echo "--- COMPLETE signal received ---" | tee -a "$LOG"
  elif grep -qE "^BLOCKED:" "$LOG"; then
    BLOCKER="$(grep -E "^BLOCKED:" "$LOG" | head -1)"
    echo "--- $BLOCKER ---" | tee -a "$LOG"
    {
      printf "\n## Blocker - %s\n\n%s\n\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$BLOCKER"
    } >> "$PROGRESS"
    echo "Blocker recorded to $PROGRESS"
  else
    echo "WARNING: No COMPLETE or BLOCKED signal found. Continuing loop..." | tee -a "$LOG"
  fi
done

FINAL_LOG="$LOGS_DIR/ratchet-final-${TIMESTAMP}.log"
echo "=== Max iterations (${MAX_ITER}) reached without full completion ===" | tee -a "$FINAL_LOG"
exit 1
