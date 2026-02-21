# Security Scan Skill

Run this skill before every commit. Detect hardcoded secrets, static analysis issues, and shell script problems.

## Steps

### 1. Hardcoded Secret Detection

Search for common secret patterns across all tracked files:

```bash
grep -rn --include="*.py" --include="*.sh" --include="*.yml" --include="*.yaml" \
  --include="*.json" --include="*.env" --include="*.conf" \
  -E "(password|secret|api_key|token|private_key)\s*[=:]\s*['\"][^'\"]{8,}" \
  . | grep -v ".ratchet/" | grep -v ".git/" || true
```

Check for untracked secret files:

```bash
find . \( -name "*.pem" -o -name "id_rsa" -o -name "*.key" -o -name ".env" \) \
  -not -name "*.example" -not -path "./.git/*" 2>/dev/null || true
```

### 2. Python Static Analysis

```bash
if command -v bandit >/dev/null 2>&1; then
  bandit -r . --exclude ./.git,./venv,./.venv -ll -q
fi
```

```bash
if command -v semgrep >/dev/null 2>&1; then
  semgrep --config=p/security . --quiet --no-git-ignore 2>/dev/null || true
fi
```

### 3. Shell Script Linting

```bash
if command -v shellcheck >/dev/null 2>&1; then
  find . -name "*.sh" -not -path "./.git/*" -exec shellcheck {} \;
fi
```

### 4. Python Type Checking

```bash
if command -v mypy >/dev/null 2>&1; then
  find . -name "*.py" -not -path "./.git/*" -not -path "./venv/*" | head -20 | xargs mypy --ignore-missing-imports 2>/dev/null || true
fi
```

## Reporting

After running all checks, report:

- `CRITICAL: <description> in <file:line>` — blocks commit, must be resolved
- `WARNING: <description> in <file:line>` — should be reviewed
- `INFO: <description>` — informational

If any CRITICAL finding exists: do NOT commit. Resolve it first, then re-run this skill.

If clean: report `Security scan clean — no issues found.`
