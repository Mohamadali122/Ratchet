#!/usr/bin/env bash
# verify.sh — Ratchet verification hook
# Runs HTTP health checks, Docker Compose service checks, JWT endpoint test,
# nginx config test, and custom shell commands.
# Reads configuration from .ratchet/verify.json
# Exit 0 = all pass, Exit 1 = one or more failures (details printed to stderr)

set -euo pipefail

VERIFY_JSON=".ratchet/verify.json"
FAILURES=""

pass() { echo "[verify] PASS: $1"; }
fail() {
  echo "[verify] FAIL: $1" >&2
  FAILURES="${FAILURES}  - $1\n"
}
info() { echo "[verify] $1"; }

# Detect python (prefer python on Windows to avoid Store stub, python3 on Linux/Mac)
PYTHON=""
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
  # On Windows, prefer 'python' as 'python3' may be a Store stub
  if command -v python >/dev/null 2>&1 && python --version >/dev/null 2>&1; then
    PYTHON="python"
  elif command -v python3 >/dev/null 2>&1 && python3 --version >/dev/null 2>&1; then
    PYTHON="python3"
  fi
else
  # On Linux/Mac, prefer python3
  if command -v python3 >/dev/null 2>&1; then
    PYTHON="python3"
  elif command -v python >/dev/null 2>&1; then
    PYTHON="python"
  fi
fi

if [[ -z "$PYTHON" ]]; then
  echo "[verify] ERROR: python3 or python not found in PATH" >&2
  exit 1
fi

if [[ ! -f "$VERIFY_JSON" ]]; then
  info "WARNING: $VERIFY_JSON not found — skipping all checks"
  exit 0
fi

# --- HTTP health checks ---
info "Running HTTP health checks..."
while IFS=$'\t' read -r url expected; do
  [[ -z "$url" ]] && continue
  actual="$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$url" 2>/dev/null || echo "000")"
  if [[ "$actual" == "$expected" ]]; then
    pass "HTTP $url → $actual"
  else
    fail "HTTP $url returned $actual (expected $expected)"
  fi
done < <("$PYTHON" - "$VERIFY_JSON" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    v = json.load(f)
for c in v.get("http_checks", []):
    print(c["url"] + "\t" + str(c.get("expected_status", 200)))
PYEOF
)

# --- Docker Compose service health ---
info "Running Docker Compose service checks..."
DOCKER_SERVICES="$("$PYTHON" - "$VERIFY_JSON" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    v = json.load(f)
for s in v.get("docker_services", []):
    print(s)
PYEOF
)"

if [[ -n "$DOCKER_SERVICES" ]]; then
  if ! command -v docker >/dev/null 2>&1; then
    info "WARNING: docker not found — skipping Docker checks"
  else
    while IFS= read -r service; do
      [[ -z "$service" ]] && continue
      state="$(docker compose ps --format json 2>/dev/null | "$PYTHON" - "$service" <<'PYEOF'
import json, sys, re
target = sys.argv[1]
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        s = json.loads(line)
        name = s.get("Service", s.get("Name", ""))
        if name == target or re.search(r"[_-]" + re.escape(target) + r"$", name):
            print(s.get("Health", s.get("State", "unknown")))
            sys.exit(0)
    except (json.JSONDecodeError, KeyError):
        pass
print("not-found")
PYEOF
      )"
      if [[ "$state" == "healthy" || "$state" == "running" ]]; then
        pass "Docker service '$service' → $state"
      else
        fail "Docker service '$service' is '$state' (expected healthy or running)"
      fi
    done <<< "$DOCKER_SERVICES"
  fi
fi

# --- JWT endpoint test ---
JWT_ENDPOINT="$("$PYTHON" - "$VERIFY_JSON" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    v = json.load(f)
ep = v.get("jwt_endpoint")
print(ep if ep else "")
PYEOF
)"

if [[ -n "$JWT_ENDPOINT" ]]; then
  info "Testing JWT endpoint: $JWT_ENDPOINT"
  status="$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$JWT_ENDPOINT" 2>/dev/null || echo "000")"
  if [[ "$status" == "000" ]]; then
    fail "JWT endpoint $JWT_ENDPOINT is unreachable"
  elif [[ "$status" == "200" || "$status" == "400" || "$status" == "401" ]]; then
    pass "JWT endpoint $JWT_ENDPOINT → $status"
  else
    fail "JWT endpoint $JWT_ENDPOINT returned unexpected status $status"
  fi
fi

# --- nginx config test ---
if command -v nginx >/dev/null 2>&1; then
  info "Testing nginx config..."
  if nginx -t 2>/dev/null; then
    pass "nginx -t"
  else
    fail "nginx config invalid (run 'nginx -t' for details)"
  fi
fi

# --- Custom checks ---
info "Running custom checks..."
while IFS=$'\t' read -r name cmd; do
  [[ -z "$name" ]] && continue
  info "Custom: $name"
  if eval "$cmd" >/dev/null 2>&1; then
    pass "$name"
  else
    fail "$name (command: $cmd)"
  fi
done < <("$PYTHON" - "$VERIFY_JSON" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    v = json.load(f)
for c in v.get("custom_checks", []):
    print(c["name"] + "\t" + c["command"])
PYEOF
)

# --- Summary ---
if [[ -z "$FAILURES" ]]; then
  info "All checks passed."
  exit 0
else
  echo "" >&2
  echo "[verify] FAILURES:" >&2
  printf "%b" "$FAILURES" >&2
  exit 1
fi
