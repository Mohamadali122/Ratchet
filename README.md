# Ratchet — Autonomous AI Agent Loop

Ratchet turns any AI coding tool into a self-driving engineering team. You define a list of tasks (a PRD). Ratchet picks the next task, delegates it to a fresh AI instance, verifies the result, commits, and loops until everything is done — or it tells you exactly why it got stuck.

> Inspired by the [Ralph pattern](https://github.com/snarktank/ralph). Cross-platform: Linux, Mac, Windows (PowerShell + Git Bash).

**What makes Ratchet different:**

- **Multi-LLM** — Claude, OpenAI, DeepSeek, Gemini, Ollama, LM Studio, Codex. Per-story model selection.
- **Parallel execution** — dispatch independent stories simultaneously with `--parallel`.
- **Web UI** — real-time dashboard with live log streaming, run/stop controls, story management.
- **Verification gate** — HTTP checks, Docker health, JWT validation, custom shell commands before every commit.
- **Authorization injection** — security and recon work handled safely via `company.md`.

---

## How It Works

```text
You write .ratchet/prd.json     (stories with acceptance criteria, deps, model overrides)
         .ratchet/company.md    (org standards, auth context)
         .ratchet/verify.json   (what "done" looks like: HTTP/Docker/custom checks)

ratchet.sh / ratchet.ps1

  reads prd.json, finds ready stories (passes: false, deps satisfied)

  serial mode:   picks highest-priority story, spawns one agent
  parallel mode: dispatches ALL ready stories simultaneously

  each agent (via ratchet_invoke.py):
      reads CLAUDE.md (operating protocol)
      implements the story (code, configs, scripts)
      runs verify.sh / verify.ps1 (acceptance gate)
      updates prd.json, progress.md
      commits with conventional commit format
      prints COMPLETE or BLOCKED: <reason>

  on COMPLETE   loop, check remaining stories
  on BLOCKED    record reason to progress.md, loop
  exits when all stories pass OR max-iter reached
```

Each iteration is logged to `logs/ratchet-TIMESTAMP[-STORYID].log`.
Cross-iteration learnings accumulate in `.ratchet/progress.md`.

---

## Prerequisites

- `claude` CLI installed and authenticated — `claude --version`
- Python >= 3.10 (`python3` or `python`)
- `git` configured with user identity
- **Linux / Mac / WSL:** `bash` >= 4.0
- **Windows:** PowerShell 5.1+ (built-in) or Git Bash
- **Web UI:** `pip install fastapi uvicorn`
- **API providers:** `pip install openai` (for OpenAI, DeepSeek, LM Studio)
- Optional: `shellcheck`, `mypy`, `docker`, `nginx`, `curl`, `ollama`

---

## Quick Start

### Linux / Mac / WSL / Git Bash

```bash
git clone https://github.com/Mohamadali122/Ratchet ratchet
cd ratchet
chmod +x ratchet.sh verify.sh ratchet_state.py

cd /path/to/your/project
/path/to/ratchet/ratchet_state.py init --name "my-feature"
/path/to/ratchet/ratchet_state.py add-story   # repeat for each task
/path/to/ratchet/ratchet.sh --project-dir . --max-iter 20
```

### Windows (PowerShell)

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

git clone https://github.com/Mohamadali122/Ratchet ratchet
cd ratchet

cd C:\Projects\myapp
python C:\path\to\ratchet\ratchet_state.py init --name "my-feature"
python C:\path\to\ratchet\ratchet_state.py add-story
C:\path\to\ratchet\ratchet.ps1 -ProjectDir . -MaxIter 20
```

### Web UI (Quick Start)

```bash
pip install fastapi uvicorn
python ratchet_ui.py --project-dir /path/to/project
# open http://localhost:7433
```

---

## Commands Reference

### State Management

| Command | What it does |
| --- | --- |
| `ratchet_state.py init --name NAME` | Create `.ratchet/` with `prd.json` and `progress.md` |
| `ratchet_state.py add-story` | Interactively add a story (criteria, deps, model override) |
| `ratchet_state.py status` | Story table: ID, DONE/READY/WAITING, model, deps |
| `ratchet_state.py reset --story S2` | Re-open a completed story |
| `ratchet_state.py ready-stories` | Print IDs of stories whose deps are satisfied |
| `ratchet_state.py mark-done --story S2` | Mark a story complete (used by parallel orchestrator) |
| `ratchet_state.py doctor` | Preflight environment check |

### Running the Loop

```bash
# Linux / Mac / Git Bash
./ratchet.sh [--tool PROVIDER] [--max-iter N] [--project-dir PATH] [--parallel]

# Windows PowerShell
.\ratchet.ps1 [-Tool PROVIDER] [-MaxIter N] [-ProjectDir PATH] [-Parallel]

# Verify checks only
./verify.sh
.\verify.ps1
```

### Web UI Dashboard

```bash
python ratchet_ui.py [--port 7433] [--host 127.0.0.1] [--project-dir PATH]
```

---

## Multi-LLM Support

Ratchet routes every agent call through `ratchet_invoke.py`, a unified adapter that normalises the invocation convention for each provider.

### Provider format: `provider` or `provider/model`

| Provider | Format | Requirement |
| --- | --- | --- |
| Claude Code | `claude` | `claude` CLI authenticated |
| Google Gemini | `gemini` or `gemini/gemini-2.0` | `gemini` CLI installed |
| OpenAI Codex | `codex` | `codex` CLI installed |
| Ollama (local) | `ollama/codellama`, `ollama/llama3` | `ollama` running locally |
| OpenAI API | `openai/gpt-4o`, `openai/gpt-4-turbo` | `OPENAI_API_KEY` + `pip install openai` |
| DeepSeek | `deepseek/deepseek-coder` | `DEEPSEEK_API_KEY` + `pip install openai` |
| LM Studio | `lmstudio/mistral` | LM Studio server at localhost:1234 |

```bash
# CLI examples
./ratchet.sh --tool claude
./ratchet.sh --tool ollama/codellama
./ratchet.sh --tool openai/gpt-4o
./ratchet.sh --tool deepseek/deepseek-coder
./ratchet.sh --tool lmstudio/mistral

# List all supported providers
python ratchet_invoke.py --list-tools
```

### Per-story model override

Set a `model` field on any story in `prd.json` to override the loop-level `--tool` for that story only:

```json
{
  "name": "my-feature",
  "branchName": "feat/my-feature",
  "stories": [
    {
      "id": "S1",
      "title": "Scaffold boilerplate files",
      "model": "ollama/codellama",
      "acceptance_criteria": ["src/ directory created", "package.json valid"],
      "passes": false
    },
    {
      "id": "S2",
      "title": "Implement complex auth logic",
      "model": "openai/gpt-4o",
      "acceptance_criteria": ["JWT validation passes", "tests exit 0"],
      "passes": false
    }
  ]
}
```

Cheap stories (boilerplate, docs) use a local model. Complex stories use a frontier model. Can cut API cost by 60–80% on large PRDs.

---

## Parallel Story Execution

Stories with satisfied dependencies run simultaneously when `--parallel` is set.

### Declaring dependencies

```json
{
  "id": "S3",
  "title": "Wire auth to API",
  "depends_on": ["S1", "S2"],
  "acceptance_criteria": ["GET /me returns user object"],
  "passes": false
}
```

Ratchet builds a DAG from `depends_on` fields. On each iteration it finds all "ready" stories (not done, all deps done) and dispatches them in parallel. Each gets its own log file (`ratchet-TIMESTAMP-SID.log`).

```bash
./ratchet.sh --parallel --max-iter 20
.\ratchet.ps1 -Parallel -MaxIter 20
```

Check which stories are currently ready without running:

```bash
./ratchet_state.py ready-stories
```

---

## Web UI Dashboard

```bash
pip install fastapi uvicorn
python ratchet_ui.py --project-dir /path/to/project
```

Open **[http://localhost:7433](http://localhost:7433)**

**Features:**

- Story table with DONE / READY / WAITING badges, model and dep info
- Stats row: complete / ready / total counts
- Run Loop button with provider selector, max-iter, and parallel toggle
- Stop button to terminate a running loop
- Per-story Reset button
- Live log stream with colour-coded output:
  - Green — `COMPLETE`
  - Red — `BLOCKED`
  - Yellow — `WARNING`

The dashboard polls `/api/status` every 2 seconds and streams logs via Server-Sent Events — no WebSockets, no build step.

---

## Project Structure

```text
ratchet/
├── ratchet.sh              # Orchestrator loop (Linux/Mac/Git Bash)
├── ratchet.ps1             # Orchestrator loop (Windows PowerShell)
├── ratchet_invoke.py       # Multi-LLM adapter (Claude/Ollama/OpenAI/DeepSeek/Gemini/...)
├── ratchet_state.py        # State management CLI (cross-platform Python)
├── ratchet_state.bat       # Windows CMD/PowerShell wrapper
├── ratchet_ui.py           # Web UI dashboard (FastAPI + SSE)
├── templates/
│   └── index.html          # Dashboard UI (HTMX + Tailwind CSS)
├── verify.sh               # Verification hook (Linux/Mac/Git Bash)
├── verify.ps1              # Verification hook (Windows PowerShell)
├── CLAUDE.md               # Agent operating protocol (auto-read by Claude Code)
├── skills/
│   ├── security-scan.md    # Secret detection, static analysis
│   ├── docker-verify.md    # Container health checks
│   ├── api-test.md         # HTTP + JWT endpoint validation
│   ├── nginx-test.md       # nginx config + proxy routing
│   └── prd-gen.md          # Guided PRD generation
└── .ratchet/               # Per-project state directory
    ├── prd.json            # Task list  (managed by ratchet_state.py)
    ├── progress.md         # Cross-iteration learnings
    ├── company.md          # Org standards, auth context
    └── verify.json         # Acceptance gate configuration
```

---

## Configuration Files

### `.ratchet/prd.json` — Task List

```json
{
  "name": "feature-name",
  "branchName": "feat/feature-name",
  "stories": [
    {
      "id": "S1",
      "title": "Action-oriented title",
      "acceptance_criteria": [
        "Specific, testable criterion",
        "Another criterion"
      ],
      "depends_on": [],
      "model": "claude",
      "passes": false
    }
  ]
}
```

`depends_on` and `model` are optional. Omit them to use list order and the loop-level `--tool`.

### `.ratchet/company.md` — Org Context

Loaded into every agent iteration. Use it to encode:

- Coding standards and style preferences
- Git conventions
- Secret management rules
- Infrastructure conventions
- **Authorization context** for security work

Any line starting with `- Authorization:` is forwarded directly into the trigger prompt so the agent sees it before applying any independent judgment.

### `.ratchet/verify.json` — Acceptance Gate

```json
{
  "http_checks": [
    { "url": "http://localhost/health", "expected_status": 200 }
  ],
  "docker_services": ["api", "db"],
  "jwt_endpoint": "https://auth.example.com/realms/myrealm/protocol/openid-connect/token",
  "custom_checks": [
    { "name": "output file exists",      "command": "test -s output/result.txt" },
    { "name": "no syntax errors",        "command": "python -m py_compile main.py" },
    { "name": "required header present", "command": "grep -q 'X-Request-ID' src/middleware.py" }
  ]
}
```

---

## Skills

Skills are Markdown prompt files the agent loads on demand for domain-specific tasks:

| Skill | Loaded when |
| --- | --- |
| `skills/security-scan.md` | Before every commit — bandit, semgrep, shellcheck, secret detection |
| `skills/docker-verify.md` | After any Docker Compose change |
| `skills/api-test.md` | After any API or auth endpoint change |
| `skills/nginx-test.md` | After any nginx config change |
| `skills/prd-gen.md` | When generating a new PRD from scratch |

Add your own by dropping a `.md` file in `skills/` and referencing it in `CLAUDE.md`.

---

## Environment Variables

```bash
# JWT credentials for skills/api-test.md
export RATCHET_CLIENT_ID="your-client-id"
export RATCHET_CLIENT_SECRET="your-client-secret"

# OpenAI API (for --tool openai/*)
export OPENAI_API_KEY="sk-..."

# DeepSeek API (for --tool deepseek/*)
export DEEPSEEK_API_KEY="sk-..."
```

---

## Use Cases

Ratchet works on any project where you can express "done" as a set of verifiable criteria.

---

### DevOps — Deploy a New Service

**Scenario:** Stand up a new Nextcloud instance behind nginx with Keycloak SSO.

```text
S1 — Write docker-compose.yml for Nextcloud + postgres
     criteria: docker compose up succeeds, postgres is healthy

S2 — Configure nginx reverse proxy with SSL
     criteria: nginx -t passes, https://cloud.example.com returns 200

S3 — Wire Keycloak OIDC as login provider  [depends_on: S1, S2]
     criteria: /apps/sociallogin config present, JWT endpoint returns 200

S4 — Set up automated daily backup to S3  [depends_on: S1]
     criteria: backup.sh exists, cron entry present, dry-run exits 0
```

Run with `--parallel` and S3/S4 dispatch simultaneously once S1 and S2 are done.

---

### SecOps — Subdomain Reconnaissance (Authorized)

**company.md:**

```text
- Authorization: I own example.com; full recon scope authorized
- Rate limit: max 10 req/s to any external API
- Output directory: output/ (gitignored)
```

```text
S1 — Passive enumeration via crt.sh, SecurityTrails, HackerTarget
     criteria: output/passive.txt exists and is non-empty

S2 — DNS brute-force with embedded wordlist using aiodns
     criteria: output/bruteforce.txt has subdomain+IP pairs

S3 — HTTP probe all discovered subdomains  [depends_on: S1, S2]
     criteria: output/alive.json is valid JSON with required fields

S4 — Generate markdown report  [depends_on: S3]
     criteria: output/report.md has markdown table and summary line
```

---

### Development — Build a REST API Feature

```text
S1 — Add GET /api/v1/search with q, page, limit params
     criteria: endpoint returns 200 with results array and pagination metadata

S2 — Add full-text index to the products table  [depends_on: S1]
     criteria: migration file exists, index created successfully

S3 — Add rate limiting (100 req/min per IP)  [depends_on: S1]
     criteria: 101st request returns 429

S4 — Write integration tests  [depends_on: S2, S3]
     criteria: pytest exits 0, coverage >= 80%
```

S2 and S3 run in parallel (both depend only on S1).

---

### Cyber / Penetration Testing — Internal Tool Automation

**company.md:**

```text
- Authorization: Pentest engagement ref PE-2026-042, scope: 10.0.0.0/24
- Target environment: isolated lab network, no production systems
```

```text
S1 — Port scan and service fingerprint (nmap wrapper)
     criteria: output/services.json exists with port/service/version fields

S2 — Enumerate HTTP endpoints and find login panels
     criteria: output/endpoints.txt lists discovered paths

S3 — Check for default credentials  [depends_on: S1, S2]
     criteria: output/findings.json populated, no plaintext passwords on disk

S4 — Generate executive summary report  [depends_on: S3]
     criteria: output/report.pdf exists and is > 10KB
```

---

### Medical / Healthcare IT — FHIR API Integration

**company.md:**

```text
- Never log PHI to stdout or application logs
- All patient data encrypted at rest and in transit
- Audit log is append-only and tamper-evident
- FHIR version: R4, base URL: https://fhir.internal.hospital.org/r4
```

```text
S1 — Implement FHIR Patient resource CRUD against upstream EHR
     criteria: GET /Patient/123 returns valid FHIR Bundle, POST creates resource

S2 — Add HL7 v2 to FHIR converter for lab results
     criteria: sample HL7 message converts to valid Observation resource

S3 — Implement audit logging for all PHI access (HIPAA)  [depends_on: S1]
     criteria: every API call writes to audit.log with user, action, timestamp, patient ID

S4 — Encrypt PHI fields at rest  [depends_on: S1]
     criteria: database dump shows encrypted values, decrypt function passes unit tests
```

---

### n8n / Workflow Automation — Build a Custom Node

```text
S1 — Scaffold n8n-nodes-myapi package with TypeScript boilerplate
     criteria: npm run build exits 0, node appears in n8n node list

S2 — Implement authentication (API key, n8n credentials)
     criteria: credential type registered, test connection returns success

S3 — Add List, Get, Create, Update, Delete operations  [depends_on: S1, S2]
     criteria: each operation has correct mapping, unit tests pass

S4 — Publish to npm and write usage docs  [depends_on: S3]
     criteria: npm publish succeeds, README has quickstart example
```

---

### Data Engineering — Build an ETL Pipeline

```text
S1 — Ingest raw CSV files from S3 and validate schema
     criteria: ingestion script exits 0, invalid rows written to quarantine/

S2 — Transform: deduplicate, normalize dates, fill nulls  [depends_on: S1]
     criteria: output row count matches expected, no null primary keys

S3 — Load into BigQuery staging table  [depends_on: S2]
     criteria: bq show staging.events succeeds, row count matches

S4 — Schedule via Airflow DAG  [depends_on: S3]
     criteria: dag.py parses without error, schedule_interval == @daily
```

---

### Infrastructure as Code — Terraform Module

```text
S1 — Define VPC, subnets, route tables
     criteria: terraform validate passes, terraform plan shows expected resources

S2 — Add NAT gateway, Internet gateway, security groups  [depends_on: S1]
     criteria: no open 0.0.0.0/0 ingress rules except ports 80/443

S3 — Add outputs: VPC ID, subnet IDs, security group IDs  [depends_on: S1]
     criteria: all outputs declared, terraform-docs generates valid README

S4 — Write terratest integration test  [depends_on: S2, S3]
     criteria: go test ./... exits 0 against sandbox AWS account
```

S2 and S3 run in parallel.

---

### SRE / Observability — Add Monitoring Stack

```text
S1 — Add /metrics endpoint to the API (Prometheus format)
     criteria: curl localhost:8000/metrics returns # HELP lines

S2 — Deploy Prometheus with scrape config  [depends_on: S1]
     criteria: Prometheus UI shows target as UP

S3 — Import Grafana dashboard  [depends_on: S2]
     criteria: dashboard JSON valid, panels visible via Grafana API

S4 — Configure alerting rule: error rate > 1% for 5m  [depends_on: S2]
     criteria: alert rule YAML valid, appears in Prometheus rules list
```

---

## Tips for Writing Good Stories

1. **One verifiable outcome per story.** If you need two things, make two stories.
2. **Acceptance criteria are shell commands.** Phrase them so they map directly to `custom_checks`.
3. **Declare dependencies explicitly.** Use `depends_on` instead of relying on list order.
4. **Front-load the foundation.** Scaffold before you build features.
5. **Keep stories under ~2 hours of human work.** If it's bigger, split it.
6. **Use `verify.json` aggressively.** The tighter the acceptance gate, the less rework.
7. **Use cheap models for boilerplate.** Set `model: ollama/codellama` on scaffolding stories.

---

## Troubleshooting

**"No COMPLETE or BLOCKED signal"** — the agent ran but didn't follow the protocol. Check `logs/ratchet-TIMESTAMP.log`. The agent may need more context in `CLAUDE.md` or `.ratchet/company.md`.

**Story stays incomplete** — run `./verify.sh` manually to see which checks fail. Check `.ratchet/progress.md` for recorded blockers.

**Agent refuses a security task** — add an `Authorization:` line to `.ratchet/company.md`:

```text
- Authorization: I own example.com; full recon scope authorized
```

**Parallel mode: stories conflict on git** — parallel agents committing to the same branch can occasionally conflict. Reset the failing story and re-run serially for that story only.

**API provider not working** — check the required env var is set (`OPENAI_API_KEY`, `DEEPSEEK_API_KEY`) and `pip install openai` is done. Run `python ratchet_invoke.py --list-tools` to see all providers.

**Web UI not starting** — run `pip install fastapi uvicorn` first.

**`claude` not found** — install: `npm install -g @anthropic-ai/claude-code`, then `claude auth`.

**PowerShell "not digitally signed":**

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

**Run preflight check:**

```bash
./ratchet_state.py doctor
```

---

## Extending Ratchet

### Add a Custom Skill

Create `skills/my-domain.md` with instructions for the agent, then reference it in `CLAUDE.md`:

```markdown
5. Run skill if applicable:
   - My domain changes -> `skills/my-domain.md`
```

### Add a New LLM Provider

Add a function to `ratchet_invoke.py` and register it in `_DISPATCH`:

```python
def invoke_myprovider(model: str, prompt: str) -> int:
    return subprocess.call(["myprovider", "--prompt", prompt])

_DISPATCH["myprovider"] = invoke_myprovider
```

Then use it with `--tool myprovider` or `--tool myprovider/model-name`.

### Chain Multiple Projects

```bash
./ratchet.sh --project-dir /srv/project-a --max-iter 20
./ratchet.sh --project-dir /srv/project-b --max-iter 20
```

---

## Future Work

Contributions are welcome.

| Item | Status |
| --- | --- |
| Multi-LLM support (Claude, OpenAI, DeepSeek, Gemini, Ollama, LM Studio) | **Done** |
| Web UI dashboard (FastAPI + HTMX + SSE log streaming) | **Done** |
| Parallel story execution with `depends_on` DAG | **Done** |
| `ratchet doctor` preflight check | **Done** |
| Story dependency graph (DAG-aware scheduling) | **Done** |
| `pip install ratchet-loop` — proper CLI packaging | Planned |
| Slack / webhook notifications on complete / blocked | Planned |
| Auto-retry blocked stories (`--retry-blocked N`) | Planned |
| `ratchet rollback` — undo last story commit | Planned |
| Token usage tracking per iteration | Planned |
| Audit log (`audit.jsonl`) for compliance | Planned |
| Secret scanning as hard gate in orchestrator | Planned |

---

## License

MIT — see [LICENSE](LICENSE).
