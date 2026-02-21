#!/usr/bin/env bash
# ratchet.sh -- Ratchet autonomous AI agent loop orchestrator
# Supports multiple LLM providers via ratchet_invoke.py and optional parallel execution.

set -euo pipefail

TOOL="claude"
MAX_ITER=20
PROJECT_DIR="."
PARALLEL=false

usage() {
  cat >&2 <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --tool TOOL         AI provider: claude (default), ollama/codellama, openai/gpt-4o,
                      deepseek, gemini, lmstudio/mistral, codex
  --max-iter N        Max iterations before giving up (default: 20)
  --project-dir PATH  Project directory containing CLAUDE.md and .ratchet/ (default: .)
  --parallel          Run all ready stories simultaneously (experimental)
  --help              Show this help

Examples:
  ./ratchet.sh --project-dir /srv/myapp --max-iter 15
  ./ratchet.sh --tool ollama/codellama --project-dir . --max-iter 10
  ./ratchet.sh --tool openai/gpt-4o --parallel --max-iter 20
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tool)        TOOL="$2";        shift 2 ;;
    --max-iter)    MAX_ITER="$2";    shift 2 ;;
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
    --parallel)    PARALLEL=true;    shift   ;;
    --help|-h)     usage ;;
    *)             echo "Unknown argument: $1" >&2; usage ;;
  esac
done

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
RATCHET_DIR="$PROJECT_DIR/.ratchet"
PRD="$RATCHET_DIR/prd.json"
PROGRESS="$RATCHET_DIR/progress.md"
LOGS_DIR="$PROJECT_DIR/logs"

if [[ ! -f "$PRD" ]]; then
  echo "ERROR: $PRD not found. Run: ./ratchet_state.py init --name <name>" >&2
  exit 1
fi

# Detect python
PYTHON=""
if command -v python3 >/dev/null 2>&1; then
  PYTHON="python3"
elif command -v python >/dev/null 2>&1; then
  PYTHON="python"
else
  echo "ERROR: python3 or python not found in PATH" >&2
  exit 1
fi

INVOKE="$PYTHON $PROJECT_DIR/ratchet_invoke.py"
STATE="$PYTHON $PROJECT_DIR/ratchet_state.py"

mkdir -p "$LOGS_DIR"

count_incomplete() {
  "$PYTHON" - "$PRD" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    prd = json.load(f)
print(len([s for s in prd.get("stories", []) if not s.get("passes", False)]))
PYEOF
}

# Return model for a given story id, falling back to $TOOL
story_tool() {
  local story_id="$1"
  "$PYTHON" - "$PRD" "$story_id" "$TOOL" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    prd = json.load(f)
sid, default = sys.argv[2], sys.argv[3]
for s in prd.get("stories", []):
    if s.get("id") == sid:
        print(s.get("model", default)); sys.exit(0)
print(default)
PYEOF
}

# Build authorization prefix from company.md
COMPANY_MD="$RATCHET_DIR/company.md"
AUTH_PREFIX=""
if [[ -f "$COMPANY_MD" ]]; then
  AUTH_LINE="$(grep -E "^- Authorization:" "$COMPANY_MD" | head -1 | sed 's/^- //')"
  if [[ -n "$AUTH_LINE" ]]; then
    AUTH_PREFIX="${AUTH_LINE} "
  fi
fi

iter=0
while [[ "$iter" -lt "$MAX_ITER" ]]; do
  iter=$((iter + 1))
  TIMESTAMP="$(date +%Y%m%dT%H%M%S)"

  incomplete="$(count_incomplete)"
  if [[ "$incomplete" -eq 0 ]]; then
    echo "=== All stories complete after $((iter - 1)) iteration(s). ==="
    exit 0
  fi

  echo "=== Iteration ${iter}/${MAX_ITER} | Incomplete: ${incomplete} | Parallel: ${PARALLEL} ==="

  # ---------------------------------------------------------------------------
  # PARALLEL MODE -- dispatch all ready stories simultaneously
  # ---------------------------------------------------------------------------
  if [[ "$PARALLEL" == "true" ]]; then
    mapfile -t ready_ids < <(cd "$PROJECT_DIR" && $STATE ready-stories)

    if [[ ${#ready_ids[@]} -eq 0 ]]; then
      echo "WARNING: No ready stories (dependency deadlock or all blocked)."
      break
    fi

    echo "Dispatching: ${ready_ids[*]}"
    declare -A pids

    for sid in "${ready_ids[@]}"; do
      log="$LOGS_DIR/ratchet-${TIMESTAMP}-${sid}.log"
      tool="$(story_tool "$sid")"
      prompt="${AUTH_PREFIX}You are running inside the Ratchet agent loop. \
Read CLAUDE.md for your full operating protocol. \
Implement ONLY story ${sid} from .ratchet/prd.json. \
Print COMPLETE when done or BLOCKED: <reason> if stuck."

      echo "  Spawning [${sid}] -> ${tool} -> ${log}"
      (cd "$PROJECT_DIR" && $INVOKE --tool "$tool" --prompt "$prompt") >"$log" 2>&1 &
      pids["$sid"]=$!
    done

    for sid in "${!pids[@]}"; do
      wait "${pids[$sid]}" || true
    done

    for sid in "${ready_ids[@]}"; do
      log="$LOGS_DIR/ratchet-${TIMESTAMP}-${sid}.log"
      if grep -qE "^COMPLETE" "$log" 2>/dev/null; then
        echo "  [${sid}] COMPLETE"
        (cd "$PROJECT_DIR" && $STATE mark-done --story "$sid")
      elif grep -qE "^BLOCKED:" "$log" 2>/dev/null; then
        BLOCKER="$(grep -E "^BLOCKED:" "$log" | head -1)"
        echo "  [${sid}] $BLOCKER"
        printf "\n## Blocker [%s] - %s\n\n%s\n\n" \
          "$sid" "$(date '+%Y-%m-%d %H:%M:%S')" "$BLOCKER" >> "$PROGRESS"
      else
        echo "  [${sid}] WARNING: No signal found."
      fi
    done
    unset pids

  # ---------------------------------------------------------------------------
  # SERIAL MODE (default)
  # ---------------------------------------------------------------------------
  else
    LOG="$LOGS_DIR/ratchet-${TIMESTAMP}.log"
    echo "Log: $LOG"
    TRIGGER="${AUTH_PREFIX}You are running inside the Ratchet agent loop. \
Read CLAUDE.md for your full operating protocol, then \
work through the next incomplete story in .ratchet/prd.json."

    set +e
    (cd "$PROJECT_DIR" && $INVOKE --tool "$TOOL" --prompt "$TRIGGER") 2>&1 | tee -a "$LOG"
    set -e

    if grep -qE "^COMPLETE" "$LOG"; then
      echo "--- COMPLETE signal received ---" | tee -a "$LOG"
    elif grep -qE "^BLOCKED:" "$LOG"; then
      BLOCKER="$(grep -E "^BLOCKED:" "$LOG" | head -1)"
      echo "--- $BLOCKER ---" | tee -a "$LOG"
      printf "\n## Blocker - %s\n\n%s\n\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$BLOCKER" >> "$PROGRESS"
      echo "Blocker recorded to $PROGRESS"
    else
      echo "WARNING: No COMPLETE or BLOCKED signal found. Continuing..." | tee -a "$LOG"
    fi
  fi
done

echo "=== Max iterations (${MAX_ITER}) reached without full completion ==="
exit 1
