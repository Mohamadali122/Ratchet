# Story Validator Skill

Run this skill before implementing any story. Ensures acceptance criteria are testable,
unambiguous, and completable in a single iteration. Catches bad stories early — before
wasted code is written.

## Steps

### 1. Load the Target Story

Read `.ratchet/prd.json` and identify the story you are about to implement:

```bash
python3 -c "
import json, sys
with open('.ratchet/prd.json') as f:
    prd = json.load(f)
stories = [s for s in prd['stories'] if not s.get('passes', False)]
if not stories:
    print('No pending stories.')
    sys.exit(0)
s = stories[0]
print(f'Story: {s[\"id\"]} — {s[\"title\"]}')
print('Acceptance criteria:')
for i, ac in enumerate(s['acceptance_criteria'], 1):
    print(f'  {i}. {ac}')
"
```

### 2. Validate Each Acceptance Criterion

For each criterion, check:

**Testability** — Can it be verified by a command, HTTP call, file check, or diff?
Bad examples (vague):
- "works correctly"
- "looks good"
- "is deployed"

Good examples (testable):
- "`curl http://localhost/health` returns 200"
- "`docker compose ps api` shows state=running"
- "File `output/report.txt` is non-empty"

**Scope** — Is it achievable in a single agent iteration (one code-write + verify cycle)?
Flag if a criterion requires:
- Multiple external system integrations from scratch
- Manual approvals or human decisions
- More than ~200 lines of net-new code

**Clarity** — Is the expected value explicit?
Flag if the criterion says "should return success" without specifying what success means.

### 3. Check Dependency Ordering

Verify that every story this one depends on already has `passes: true`:

```bash
python3 -c "
import json
with open('.ratchet/prd.json') as f:
    prd = json.load(f)
stories = prd['stories']
pending = [s for s in stories if not s.get('passes', False)]
if not pending:
    print('All stories complete.')
else:
    target = pending[0]
    passed_ids = {s['id'] for s in stories if s.get('passes', False)}
    deps = target.get('depends_on', [])
    blocked = [d for d in deps if d not in passed_ids]
    if blocked:
        print(f'BLOCKED: story {target[\"id\"]} depends on unfinished: {blocked}')
    else:
        print(f'Dependencies satisfied for {target[\"id\"]}')
"
```

### 4. Estimate Scope

Count lines of existing code in the affected area as a baseline:

```bash
# Count lines in likely-affected directories
find . -name "*.py" -o -name "*.sh" -o -name "*.yml" \
  | grep -v ".git/" | grep -v "venv/" \
  | xargs wc -l 2>/dev/null | tail -1 || true
```

## Reporting

- All criteria testable, scope reasonable, dependencies satisfied → `Story validation PASSED — proceed with implementation`
- Vague criterion found → `WARNING: criterion "<text>" is not verifiable — suggest rewriting as a command or assertion`
- Dependency unmet → `BLOCKED: depends on <story-id> which has not passed`
- Story too large → `WARNING: story may exceed single-iteration scope — consider splitting`

If any BLOCKED finding: do NOT start implementation. Print `BLOCKED: <reason>` and exit 1.
If only WARNINGs: document them in `.ratchet/progress.md` and proceed with caution.
