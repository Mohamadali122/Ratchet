# Progress Writer Skill

Run this skill when updating `.ratchet/progress.md` after completing or being blocked on a story.
Structured entries make cross-iteration memory useful. Raw dumps do not.

## When to Write

- After marking a story `passes: true` — record what worked
- After emitting BLOCKED — record what failed and why
- After discovering a non-obvious pattern — record it immediately

## Entry Format

Each entry must follow this structure:

```markdown
## [YYYY-MM-DD] <Story ID>: <Story Title> — <PASSED | BLOCKED>

### What was done
<1-3 sentences: the approach taken, files changed, commands run>

### Key findings
- <Specific, reusable pattern or fact — e.g., "nginx reload requires `systemctl reload nginx`, not restart">
- <Gotcha or non-obvious behavior — e.g., "Docker Compose v2 outputs JSON per-line, not as array">
- <Tool quirk — e.g., "bandit -ll skips low-severity; use -l to catch all">

### Commands that worked
```bash
# The exact command(s) that solved the problem or verified success
<command>
```

### What failed / why blocked (if applicable)
- <Root cause of the failure>
- <What was tried>
- <What the operator needs to provide or fix>

### Watch out for
- <Anything that will trip up future iterations on related stories>
```

## How to Append

```bash
python3 -c "
import datetime
entry = '''
## [{date}] {story_id}: {title} -- {status}

### What was done
{what_done}

### Key findings
{findings}

### Commands that worked
\`\`\`bash
{commands}
\`\`\`
'''.format(
    date=datetime.date.today().isoformat(),
    story_id='S1',
    title='Example Story',
    status='PASSED',
    what_done='Describe approach here.',
    findings='- Finding 1\n- Finding 2',
    commands='# example command'
)
with open('.ratchet/progress.md', 'a') as f:
    f.write(entry)
print('progress.md updated')
"
```

## Quality Rules

**Do write:**
- Exact commands that succeeded (copy-pasteable)
- Exact error messages encountered and their fix
- File paths that were non-obvious to locate
- Version-specific behavior (e.g., "Docker Compose v2.x vs v1.x")
- Environment variable names required

**Do NOT write:**
- Vague statements: "it worked after fixing the config"
- Redundant info already in prd.json (story titles, acceptance criteria)
- Sensitive values: tokens, passwords, client secrets
- Long stack traces — summarize to the root cause line

## Searching Past Entries

Before starting a new story, search progress.md for relevant prior learnings:

```bash
grep -n "<keyword>" .ratchet/progress.md | head -20
```

Keywords to try: service name, tool name, error keyword, story ID of similar work.

## Reporting

After writing: `progress.md updated — <N> entries total`

```bash
grep -c "^## \[" .ratchet/progress.md 2>/dev/null || echo "0"
```
