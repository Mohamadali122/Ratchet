# Ratchet — AI Agent Loop

So here's the idea. You have a project. Instead of spending hours prompting Claude back and forth, you write down what you want done as a list of tasks, point Ratchet at your project, and let it run. Ratchet keeps spawning AI agents, one task at a time (or several at once), until everything is done — or it tells you exactly where it got stuck.

Think of it like a project manager that never sleeps, never forgets context, and signs off on every task before moving to the next one.

> Inspired by the [Ralph pattern](https://github.com/snarktank/ralph). Works on Linux, Mac, and Windows.

---

## What makes it different from just prompting Claude yourself?

- **It loops.** One prompt → one story done → loop → next story. You walk away.
- **It verifies.** Before marking anything done, it runs your actual checks (HTTP, Docker, custom scripts). No hallucinated "done".
- **It remembers.** Learnings from each iteration get written to `progress.md` so the next agent knows what the previous one figured out.
- **It parallelises.** Got 4 independent tasks? Fire 4 agents at the same time.
- **It works with any AI.** Claude, GPT-4o, Gemini, DeepSeek, Ollama (local), LM Studio — swap at any time.
- **It has a UI.** Real-time dashboard at `localhost:7433` if you don't want to stare at a terminal.

---

## How does it actually work?

```text
You write a task list  →  prd.json
You define "done"      →  verify.json
You run ratchet        →  it does the rest

For each iteration:
  1. Find the next task that's ready (all its dependencies are done)
  2. Spawn an AI agent with your task as a prompt
  3. Agent writes the code / config / scripts
  4. Agent runs your verify checks
  5. If checks pass → mark task done, commit, loop
  6. If checks fail → write why to progress.md, loop
  7. Stop when everything is done (or you hit max iterations)
```

Each run gets its own log file. The agent prints `COMPLETE` when it finishes a task, or `BLOCKED: <reason>` if it can't. The orchestrator reads that signal and decides what to do next.

---

## Before you start

You need:

- `claude` CLI — install with `npm install -g @anthropic-ai/claude-code` then `claude auth`
- Python 3.10+
- git (with your name/email configured)

Optional:

- `pip install fastapi uvicorn` — for the web UI
- `pip install openai` — for OpenAI, DeepSeek, or LM Studio
- Docker, shellcheck, curl — depending on what your tasks need

---

## Getting started

### On Linux / Mac / WSL

```bash
git clone https://github.com/Mohamadali122/Ratchet ratchet
cd ratchet
chmod +x ratchet.sh verify.sh ratchet_state.py

# Go to your project
cd /path/to/your/project

# Set up the task list
/path/to/ratchet/ratchet_state.py init --name "my-feature"
/path/to/ratchet/ratchet_state.py add-story   # run this once per task

# Run it
/path/to/ratchet/ratchet.sh --project-dir . --max-iter 20
```

### On Windows (PowerShell)

```powershell
git clone https://github.com/Mohamadali122/Ratchet ratchet

cd C:\Projects\myapp
python C:\path\to\ratchet\ratchet_state.py init --name "my-feature"
python C:\path\to\ratchet\ratchet_state.py add-story
C:\path\to\ratchet\ratchet.ps1 -ProjectDir . -MaxIter 20
```

### With the Web UI

```bash
pip install fastapi uvicorn
python ratchet_ui.py --project-dir /path/to/project
# open http://localhost:7433
```

---

## The task list — prd.json

This is the heart of everything. It lives in `.ratchet/prd.json` in your project.

```json
{
  "name": "my-feature",
  "branchName": "feat/my-feature",
  "stories": [
    {
      "id": "S1",
      "title": "Set up the database schema",
      "acceptance_criteria": [
        "migrations/001_init.sql creates users and jobs tables",
        "python -m py_compile check_db.py exits 0"
      ],
      "depends_on": [],
      "passes": false
    },
    {
      "id": "S2",
      "title": "Build the REST API",
      "acceptance_criteria": [
        "GET /health returns 200",
        "POST /jobs creates a record and returns the new ID"
      ],
      "depends_on": ["S1"],
      "passes": false
    }
  ]
}
```

A few things to know:

- `passes: false` means not done yet. The agent sets it to `true` when it finishes.
- `depends_on` means "don't start this until those are done". Leave it empty if the task has no dependencies.
- `acceptance_criteria` are the actual tests the agent runs to verify its work. Be specific — vague criteria lead to vague results.
- You can also add a `model` field per story if you want a specific AI for that task (more on that below).

---

## The verification gate — verify.json

Before marking any task done, Ratchet runs the checks in `.ratchet/verify.json`. If anything fails, the task doesn't pass.

```json
{
  "http_checks": [
    { "url": "http://localhost/health", "expected_status": 200 }
  ],
  "docker_services": ["api", "db"],
  "jwt_endpoint": "https://auth.example.com/realms/myrealm/protocol/openid-connect/token",
  "custom_checks": [
    { "name": "output file exists",  "command": "test -s output/result.txt" },
    { "name": "no syntax errors",    "command": "python -m py_compile main.py" }
  ]
}
```

On Windows, use Python one-liners in custom_checks instead of bash:

```json
{ "name": "file exists", "command": "python -c \"import sys,os; sys.exit(0 if os.path.exists('output/result.txt') else 1)\"" }
```

---

## Running it

```bash
# Linux / Mac
./ratchet.sh --tool claude --max-iter 20 --project-dir .

# Windows PowerShell
.\ratchet.ps1 -Tool claude -MaxIter 20 -ProjectDir .

# Run multiple tasks at the same time (parallel mode)
./ratchet.sh --parallel --max-iter 20
.\ratchet.ps1 -Parallel -MaxIter 20
```

---

## Parallel mode — running tasks simultaneously

If you have tasks that don't depend on each other, Ratchet can run them at the same time. Say you have:

```text
S1 → foundation (must go first)
S2 → nginx config  (needs S1)
S3 → Dockerfile    (needs S1)
S4 → CI pipeline   (needs S2 and S3)
```

With `--parallel`, as soon as S1 is done, S2 and S3 both start immediately — two Claude agents working at the same time. Once both are done, S4 starts. This can cut your total runtime roughly in half on a typical project.

Each parallel story gets its own log file so nothing gets mixed up.

---

## Skills

Skills are Markdown prompt files in `skills/` that the agent loads at specific points in the protocol. You don't call them manually — `CLAUDE.md` tells the agent exactly when to load each one.

| Skill | When the agent loads it |
| --- | --- |
| `story-validator.md` | Before writing a single line of code — checks acceptance criteria are testable and all deps are satisfied |
| `test-gen.md` | After implementing — generates pytest, curl, and bash tests before verify runs |
| `security-scan.md` | Before every commit — bandit, semgrep, shellcheck, secret detection |
| `blocked-recovery.md` | Before giving up — self-diagnosis checklist to attempt recovery before emitting BLOCKED |
| `progress-writer.md` | After every story outcome — enforces a structured format so cross-iteration memory is actually useful |
| `docker-verify.md` | After any Docker Compose change |
| `nginx-test.md` | After any nginx config change |
| `api-test.md` | After any API or auth endpoint change |
| `keycloak-verify.md` | After any Keycloak realm, client, or SSO change — validates token, roles, protected endpoints |
| `prd-gen.md` | When generating a new PRD from scratch |

To add your own: drop a `.md` file in `skills/` and reference it in `CLAUDE.md` under step 7.

---

## Using different AI models

You can use any of these as your agent:

| Provider | What to pass | What you need |
| --- | --- | --- |
| Claude | `claude` | `claude` CLI authenticated |
| OpenAI | `openai/gpt-4o` | `OPENAI_API_KEY` env var |
| DeepSeek | `deepseek/deepseek-coder` | `DEEPSEEK_API_KEY` env var |
| Gemini | `gemini` | `gemini` CLI installed |
| Ollama (local) | `ollama/llama3` | Ollama running locally |
| LM Studio | `lmstudio/mistral` | LM Studio server at localhost:1234 |
| Codex | `codex` | `codex` CLI installed |

```bash
./ratchet.sh --tool openai/gpt-4o
./ratchet.sh --tool ollama/codellama
```

You can even set a different model per task. Useful if you want cheap local models for simple stuff (scaffolding, docs) and a frontier model for the complex parts:

```json
{
  "id": "S1",
  "title": "Create folder structure",
  "model": "ollama/codellama",
  "acceptance_criteria": ["src/ and tests/ directories exist"],
  "passes": false
},
{
  "id": "S2",
  "title": "Implement JWT auth",
  "model": "openai/gpt-4o",
  "acceptance_criteria": ["token validation passes unit tests"],
  "passes": false
}
```

This can cut API costs by 60–80% on large projects.

---

## The org context file — company.md

`.ratchet/company.md` gets loaded into every agent iteration. Put anything you always want the agent to know:

- Your coding standards
- Git conventions
- Which secrets manager to use
- Infrastructure preferences
- Authorization for security work

```markdown
- Authorization: I own example.com and have full recon scope authorized
- Always use environment variables for secrets, never hardcode
- Git: conventional commits (feat/fix/chore), squash before PR
- Docker: always pin image versions, never use :latest
```

Any line starting with `- Authorization:` gets injected directly into the prompt — this is how you authorize security or recon tasks without the agent second-guessing you.

---

## The state management CLI

```bash
# Set up a new project
ratchet_state.py init --name "my-feature"

# Add tasks interactively
ratchet_state.py add-story

# See where things stand
ratchet_state.py status

# Re-open a task that passed (so it runs again)
ratchet_state.py reset --story S2

# See which tasks are ready right now
ratchet_state.py ready-stories

# Check your environment before running
ratchet_state.py doctor
```

On Windows replace `ratchet_state.py` with `python ratchet_state.py`.

---

## The Web UI

```bash
pip install fastapi uvicorn
python ratchet_ui.py --project-dir /path/to/project
```

Open **[http://localhost:7433](http://localhost:7433)**

You get a dashboard showing every task with a DONE / READY / WAITING badge, live log streaming as the agent works, run/stop controls, and per-task reset buttons. No build step, no npm, no webpack — just open and use it.

---

## What files does it create?

```text
your-project/
├── .ratchet/
│   ├── prd.json        ← your task list (you write this)
│   ├── verify.json     ← your acceptance checks (you write this)
│   ├── company.md      ← your org context (you write this)
│   └── progress.md     ← cross-iteration learnings (Ratchet writes this)
└── logs/
    └── ratchet-20260222T143012.log   ← one log per run
```

And Ratchet itself lives separately:

```text
ratchet/
├── ratchet.sh / ratchet.ps1    ← the main loop
├── ratchet_invoke.py           ← the multi-LLM adapter
├── ratchet_state.py            ← the CLI tool
├── ratchet_ui.py               ← the web dashboard
├── verify.sh / verify.ps1      ← runs your verify.json checks
├── CLAUDE.md                   ← tells the agent how to behave
└── skills/                     ← domain-specific prompt modules
    ├── security-scan.md
    ├── docker-verify.md
    ├── api-test.md
    ├── nginx-test.md
    └── prd-gen.md
```

---

## What can you use it for?

Honestly anything where you can write "done" as a testable condition. Here are some real examples:

### Stand up a new service (DevOps)

```text
S1 → docker-compose.yml for app + postgres
S2 → nginx reverse proxy config
S3 → Keycloak SSO wiring        (needs S1, S2)
S4 → automated S3 backups       (needs S1)
```

### Subdomain recon (SecOps / pentest)

```text
S1 → passive enumeration (crt.sh, SecurityTrails)
S2 → DNS brute-force
S3 → HTTP probe all results      (needs S1, S2)
S4 → generate markdown report   (needs S3)
```

### Build a REST API feature

```text
S1 → add GET /search endpoint
S2 → add full-text database index   (needs S1)
S3 → add rate limiting              (needs S1)
S4 → write integration tests        (needs S2, S3)
```

### Terraform module

```text
S1 → VPC, subnets, route tables
S2 → NAT gateway, security groups   (needs S1)
S3 → outputs and docs               (needs S1)
S4 → terratest integration test     (needs S2, S3)
```

### ETL pipeline

```text
S1 → ingest CSVs from S3, validate schema
S2 → deduplicate, normalize, fill nulls  (needs S1)
S3 → load to BigQuery staging            (needs S2)
S4 → schedule via Airflow                (needs S3)
```

---

## Tips for writing good tasks

1. **Be specific.** "Add a login endpoint" is vague. "POST /auth/login accepts email+password and returns a JWT" is testable.
2. **One outcome per story.** If you need two things, make two stories — they might be able to run in parallel.
3. **Write acceptance criteria like shell commands.** "pytest exits 0" is better than "tests pass".
4. **Put the foundation first.** Scaffold folders and configs before building features.
5. **Use verify.json aggressively.** The tighter the gate, the less rework.
6. **Split big tasks.** If something would take you more than a couple of hours, split it.

---

## Something went wrong?

**"No COMPLETE or BLOCKED signal"** — the agent ran but didn't follow the protocol. Check the log file in `logs/`. Usually means the agent needs more context in `CLAUDE.md` or `company.md`.

**Task keeps failing verification** — run `./verify.sh` (or `.\verify.ps1`) manually to see exactly which check is failing.

**Agent refuses a security task** — add an Authorization line to `company.md`:

```text
- Authorization: I own example.com, full recon scope authorized
```

**`claude` not found** — `npm install -g @anthropic-ai/claude-code` then `claude auth`.

**Parallel agents conflict on git** — happens occasionally when two agents commit at the same time. Reset the failing story and re-run without `--parallel` for just that story.

**PowerShell "not digitally signed":**

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

**Not sure if your environment is set up correctly:**

```bash
./ratchet_state.py doctor
```

---

## Environment variables

```bash
RATCHET_CLIENT_ID       # JWT client ID (for api-test.md skill)
RATCHET_CLIENT_SECRET   # JWT client secret (for api-test.md skill)
OPENAI_API_KEY          # needed for --tool openai/*
DEEPSEEK_API_KEY        # needed for --tool deepseek/*
```

---

## Adding your own stuff

**Custom skill** — drop a `.md` file in `skills/` with instructions, then reference it in `CLAUDE.md`. The agent will load it when relevant.

**New AI provider** — add a function to `ratchet_invoke.py` and register it:

```python
def invoke_myprovider(model: str, prompt: str) -> int:
    return _run(["myprovider", "--prompt", prompt])

_DISPATCH["myprovider"] = invoke_myprovider
```

Then `--tool myprovider` or `--tool myprovider/model-name` works automatically.

---

## What's coming next

| Feature | Status |
| --- | --- |
| Multi-LLM (Claude, OpenAI, DeepSeek, Gemini, Ollama, LM Studio) | Done |
| Web UI dashboard with live log streaming | Done |
| Parallel execution with dependency graph | Done |
| `ratchet doctor` preflight check | Done |
| `pip install ratchet-loop` packaging | Planned |
| Slack / webhook notifications | Planned |
| Auto-retry blocked stories | Planned |
| `ratchet rollback` — undo last commit | Planned |
| Token usage tracking | Planned |
| Secret scanning as a hard gate | Planned |

---

## License

MIT — see [LICENSE](LICENSE).
