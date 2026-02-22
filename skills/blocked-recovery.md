# Blocked Recovery Skill

Run this skill when you are about to emit `BLOCKED: <reason>`. Before giving up,
work through this self-diagnosis checklist. Many BLOCKED states are recoverable.

## Recovery Protocol

### Step 1: Classify the Blockage

Identify which category applies:

| Category | Symptoms |
|---|---|
| **Missing dependency** | Command not found, package not installed |
| **Environment missing** | Env var unset, config file absent |
| **Test failure** | verify.sh fails, specific check fails |
| **Logic error** | Code written but produces wrong output |
| **Acceptance criteria ambiguous** | Cannot determine when "done" is met |
| **External system unavailable** | Docker not running, network unreachable |
| **Permissions** | Cannot write file, cannot run command |

### Step 2: Attempt Self-Recovery by Category

#### Missing dependency
```bash
# Check what is actually installed
which <tool> 2>/dev/null || echo "not found"
pip list 2>/dev/null | grep <package> || true
npm list -g 2>/dev/null | grep <package> || true
```
If installable without sudo: install it. If requires sudo: document in progress.md.

#### Environment missing
```bash
# List all relevant env vars
env | grep -iE "ratchet|client|secret|token|db|host|port" | sed 's/=.*/=<redacted>/'
```
If var is missing: check `.ratchet/company.md` for hints. If not found, document
the required var name in BLOCKED message so the operator can set it.

#### Test failure — verify.sh returns non-zero
```bash
# Run verify.sh with verbose output to isolate the failing check
bash -x ./verify.sh 2>&1 | tail -40
```
Read the specific error. Attempt to fix the underlying cause rather than skipping the check.

#### Logic error — wrong output
Re-read the acceptance criterion. Check:
- Is the output format exactly right? (JSON vs plain text, trailing newline, etc.)
- Is the script executable? (`chmod +x`)
- Is the path correct relative to the working directory?

```bash
# Quick sanity checks
ls -la <output-file> 2>/dev/null || echo "file missing"
python3 -m py_compile <script.py> 2>/dev/null && echo "syntax ok" || echo "syntax error"
bash -n <script.sh> 2>/dev/null && echo "syntax ok" || echo "syntax error"
```

#### Acceptance criteria ambiguous
Re-read `.ratchet/prd.json` story carefully. Check `.ratchet/progress.md` for
prior learnings on the same topic. If still ambiguous after both checks, emit:
`BLOCKED: acceptance criterion "<text>" is ambiguous — needs clarification from operator`

#### External system unavailable
```bash
# Check Docker
docker info 2>&1 | head -5 || echo "Docker not running"
docker compose ps 2>/dev/null || echo "no compose services"

# Check network
curl -s --max-time 5 http://localhost/ -o /dev/null -w "%{http_code}" || echo "no response"
```
If Docker is not running: `BLOCKED: Docker daemon not running — start Docker first`

#### Permissions
```bash
ls -la <target-file-or-dir> 2>/dev/null
id
```
Try `chmod` if the file belongs to the current user. Document if root is required.

### Step 3: Retry

After applying any fix, retry the failed step once:
- Re-run the specific failing command
- Re-run `./verify.sh`

If it passes: continue with the story (do NOT emit BLOCKED).
If it still fails: proceed to Step 4.

### Step 4: Partial Progress Checkpoint

Before emitting BLOCKED, commit any partial work that is stable:

```bash
git add -p   # Stage only clean, working changes
# Do NOT commit broken or half-finished code
```

If nothing is clean to commit, do not commit.

### Step 5: Write a Useful BLOCKED Message

Format:
```
BLOCKED: <root cause> — <what was tried> — <what the operator needs to do>
```

Examples:
- `BLOCKED: RATCHET_CLIENT_SECRET not set — checked .ratchet/company.md, not defined — operator must export RATCHET_CLIENT_SECRET before re-running`
- `BLOCKED: verify.sh check "output exists" fails — output/report.txt not generated — upstream API returned 503 during test`
- `BLOCKED: docker compose up fails — port 5432 already bound — stop conflicting Postgres process first`

## What NOT to Do

- Do NOT emit BLOCKED because a command is not installed — install it (if possible) or find an alternative
- Do NOT emit BLOCKED because a test is slow — wait for it
- Do NOT skip verify.sh to avoid a BLOCKED state
- Do NOT delete files or reset branches as a recovery shortcut
