# Test Generation Skill

Run this skill after implementing a story and before running verify.sh.
Generates targeted unit and integration tests for new or changed code.
Tests must pass before the commit is made.

## When to Apply

| Change type | Test type to generate |
|---|---|
| New Python function/class | pytest unit test |
| New bash script | bats or bash -n + functional test |
| New HTTP endpoint | curl-based integration test |
| New Docker Compose service | compose health + smoke test |
| New config file | syntax validation test |

## Steps

### 1. Identify Changed Files

```bash
git diff --name-only HEAD 2>/dev/null || git status --short | awk '{print $2}'
```

Focus test generation on files added or modified in this story.

### 2. Generate Python Unit Tests

For each new or changed `.py` file, create a corresponding test file if one does not exist:

**Test file location:** `tests/test_<module_name>.py`

**Template for a new module `foo.py`:**

```python
# tests/test_foo.py
import pytest
# Replace with actual imports from the module under test
# from foo import function_name

class TestFunctionName:
    def test_happy_path(self):
        """Describe what normal input should produce."""
        # result = function_name(valid_input)
        # assert result == expected_output
        pass

    def test_edge_case_empty(self):
        """Empty or None input should not raise unhandled exception."""
        # with pytest.raises(ValueError):
        #     function_name(None)
        pass

    def test_returns_expected_type(self):
        """Return type matches documented interface."""
        pass
```

Rules for test quality:
- Each test has one assertion focus
- Test names describe behaviour, not implementation (`test_returns_200_for_valid_token`, not `test_api_1`)
- No hardcoded secrets — use `os.environ.get("VAR", "test-value")` for env-dependent values
- Use `pytest.mark.skipif` for tests that require external services

### 3. Generate Bash Script Tests

For new `.sh` scripts, verify at minimum:

```bash
# Syntax check
bash -n <script.sh> && echo "syntax ok" || echo "FAIL: syntax error"

# ShellCheck
shellcheck <script.sh> && echo "shellcheck ok" || echo "FAIL: shellcheck"

# Dry-run / smoke test (if the script supports it)
# bash <script.sh> --dry-run 2>&1 | head -10
```

### 4. Generate HTTP Endpoint Tests

For new API routes, generate curl-based assertions:

```bash
# Template — replace URL, method, expected status
BASE_URL="${BASE_URL:-http://localhost}"

# Test 1: endpoint exists and returns expected status
actual=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${BASE_URL}/path")
expected="200"
if [[ "$actual" == "$expected" ]]; then
  echo "PASS: GET /path returns $expected"
else
  echo "FAIL: GET /path returned $actual, expected $expected"
fi

# Test 2: protected endpoint rejects unauthenticated request
actual_unauth=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${BASE_URL}/protected-path")
if [[ "$actual_unauth" == "401" ]]; then
  echo "PASS: /protected-path returns 401 without token"
else
  echo "FAIL: /protected-path returned $actual_unauth, expected 401"
fi
```

### 5. Run the Tests

```bash
# Python tests
if command -v pytest >/dev/null 2>&1 && ls tests/test_*.py >/dev/null 2>&1; then
  pytest tests/ -v --tb=short 2>&1
fi

# Bash syntax tests
for f in $(git diff --name-only HEAD | grep '\.sh$'); do
  bash -n "$f" && echo "PASS: $f syntax ok" || echo "FAIL: $f syntax error"
  shellcheck "$f" 2>&1 && echo "PASS: $f shellcheck" || echo "FAIL: $f shellcheck"
done
```

### 6. Fix Failures Before Proceeding

If any test fails:
1. Read the failure output carefully
2. Fix the implementation (not the test, unless the test is wrong)
3. Re-run the failing test in isolation before re-running the full suite
4. Do NOT proceed to verify.sh with failing tests

## Adding Tests to verify.json

For tests that should run every iteration, add them as custom_checks:

```json
{
  "custom_checks": [
    { "name": "unit tests pass", "command": "python -m pytest tests/ -q" },
    { "name": "no syntax errors in scripts", "command": "bash -n ratchet.sh" }
  ]
}
```

## Reporting

- All tests pass → `Test generation PASSED — <N> tests, all green`
- Test failures → `FAIL: <test name> — <error summary>` — fix before committing
- No testable code changed → `Test generation skipped — no testable changes detected`
