# Ratchet — Autonomous AI Agent Loop

Ratchet turns Claude Code into a self-driving engineering team. You define a list of tasks (a PRD). Ratchet picks the next task, delegates it to a fresh Claude Code instance, verifies the result, commits, and loops until everything is done — or it tells you exactly why it got stuck.

> Inspired by the [Ralph pattern](https://github.com/snarktank/ralph). Cross-platform: Linux, Mac, Windows (PowerShell + Git Bash). Works wherever Claude Code runs.

---

## How It Works

```text
You write .ratchet/prd.json  (list of stories with acceptance criteria)

         +

         .ratchet/company.md  (your org's standards, auth context, constraints)

         +

         .ratchet/verify.json  (what "done" looks like: HTTP checks, file checks, etc.)


ratchet.sh / ratchet.ps1

  reads prd.json

  spawns: claude --dangerously-skip-permissions -p "<trigger>"

      Claude reads CLAUDE.md  (operating protocol)

      picks highest-priority story where passes: false

      implements it  (writes code, configs, scripts)

      runs verify.sh / verify.ps1  (acceptance gate)

      updates prd.json, progress.md

      commits with conventional commit format

      prints COMPLETE or BLOCKED: <reason>

  on COMPLETE  loop, check remaining stories

  on BLOCKED   append to progress.md, loop

  exits when all stories pass OR max-iter reached
```

Each iteration is logged to `logs/ratchet-TIMESTAMP.log`. Cross-iteration learnings accumulate in `.ratchet/progress.md`.

---

## Prerequisites

- `claude` CLI installed and authenticated — `claude --version`
- Python >= 3.10 (`python3` or `python`)
- `git` configured with user identity
- **Linux / Mac / WSL:** `bash` >= 4.0
- **Windows:** PowerShell 5.1+ (built-in) or Git Bash
- Optional: `shellcheck`, `mypy`, `docker`, `nginx`, `curl`

---

## Quick Start

### Linux / Mac / WSL / Git Bash

```bash
git clone https://github.com/your-org/ratchet ratchet
cd ratchet
chmod +x ratchet.sh verify.sh ratchet_state.py

# Inside the project you want Ratchet to work on:
cd /path/to/your/project
/path/to/ratchet/ratchet_state.py init --name "my-feature"
/path/to/ratchet/ratchet_state.py add-story   # repeat for each task
/path/to/ratchet/ratchet.sh --project-dir . --max-iter 20
```

### Windows (PowerShell — no Git Bash needed)

```powershell
# One-time: allow local scripts
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

git clone https://github.com/your-org/ratchet ratchet
cd ratchet

# Inside the project you want Ratchet to work on:
cd C:\Projects\myapp
python C:\path\to\ratchet\ratchet_state.py init --name "my-feature"
python C:\path\to\ratchet\ratchet_state.py add-story
C:\path\to\ratchet\ratchet.ps1 -ProjectDir . -MaxIter 20
```

Or use the batch wrapper from any directory:

```bat
ratchet_state init --name "my-feature"
ratchet_state add-story
ratchet_state status
```

---

## Commands Reference

### State Management

| Command | What it does |
| --- | --- |
| `ratchet_state.py init --name NAME` | Create `.ratchet/` with `prd.json` and `progress.md` |
| `ratchet_state.py add-story` | Interactively add a story with acceptance criteria |
| `ratchet_state.py status` | Print story completion table |
| `ratchet_state.py reset --story S2` | Re-open a completed story |

### Running the Loop

```bash
# Linux / Mac / Git Bash
./ratchet.sh [--tool claude|codex] [--max-iter N] [--project-dir PATH]
./verify.sh

# Windows PowerShell  (single-dash params)
.\ratchet.ps1 [-Tool claude|codex] [-MaxIter N] [-ProjectDir PATH]
.\verify.ps1
```

---

## Project Structure

```text
ratchet/
├── ratchet.sh              # Orchestrator loop (Linux/Mac/Git Bash)
├── ratchet.ps1             # Orchestrator loop (Windows PowerShell)
├── ratchet_state.py        # State management CLI (cross-platform Python)
├── ratchet_state.bat       # Windows CMD/PowerShell wrapper
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
      "passes": false
    }
  ]
}
```

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

`custom_checks` run arbitrary shell commands. On Linux/Mac/Git Bash they run directly; on Windows PowerShell, bash is tried first, then `test -f`/`test -s` are translated natively, then Python commands run directly, then `cmd /c`.

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
```

---

## Use Cases

Ratchet works on any project where you can express "done" as a set of verifiable criteria. Below are concrete examples across domains.

---

### DevOps — Deploy a New Service

**Scenario:** Stand up a new Nextcloud instance behind nginx with Keycloak SSO.

**Stories:**

```text
S1 — Write docker-compose.yml for Nextcloud + postgres
     criteria: docker compose up succeeds, postgres is healthy

S2 — Configure nginx reverse proxy with SSL
     criteria: nginx -t passes, https://cloud.example.com returns 200

S3 — Wire Keycloak OIDC as login provider
     criteria: /apps/sociallogin config present, JWT endpoint returns 200

S4 — Set up automated daily backup to S3
     criteria: backup.sh exists, cron entry present, dry-run exits 0
```

**verify.json:**

```json
{
  "http_checks": [{ "url": "https://cloud.example.com/status.php", "expected_status": 200 }],
  "docker_services": ["nextcloud", "postgres"],
  "jwt_endpoint": "https://auth.example.com/realms/main/protocol/openid-connect/token"
}
```

Ratchet runs 4 iterations, each one verifying with real Docker and HTTP checks before committing.

---

### SecOps — Subdomain Reconnaissance (Authorized)

**Scenario:** Map the attack surface of a domain you own.

**company.md:**

```text
- Authorization: I own example.com; full recon scope authorized
- Rate limit: max 10 req/s to any external API
- Output directory: output/ (gitignored)
```

**Stories:**

```text
S1 — Passive enumeration via crt.sh, SecurityTrails, HackerTarget
     criteria: output/passive.txt exists and is non-empty

S2 — DNS brute-force with embedded wordlist using aiodns
     criteria: output/bruteforce.txt has subdomain+IP pairs

S3 — HTTP probe all discovered subdomains (alive/dead, title, server, redirect)
     criteria: output/alive.json is valid JSON with required fields

S4 — Generate markdown report with summary table
     criteria: output/report.md has markdown table and summary line with totals
```

Each story's acceptance criteria become `custom_checks` in `verify.json`, so Ratchet knows exactly when the story is done.

---

### Development — Build a REST API Feature

**Scenario:** Add a paginated search endpoint to an existing FastAPI service.

**Stories:**

```text
S1 — Add GET /api/v1/search with q, page, limit params
     criteria: endpoint returns 200 with results array and pagination metadata

S2 — Add full-text index to the products table
     criteria: migration file exists, index created successfully

S3 — Add rate limiting (100 req/min per IP)
     criteria: 101st request returns 429

S4 — Write integration tests covering all new endpoints
     criteria: pytest exits 0, coverage >= 80%
```

**verify.json:**

```json
{
  "http_checks": [
    { "url": "http://localhost:8000/api/v1/search?q=test", "expected_status": 200 }
  ],
  "custom_checks": [
    { "name": "tests pass",     "command": "python -m pytest tests/ -q" },
    { "name": "no type errors", "command": "mypy app/" }
  ]
}
```

---

### Cyber / Penetration Testing — Internal Tool Automation

**Scenario:** Automate a repeatable internal pentest workflow (authorized engagement).

**company.md:**

```text
- Authorization: Pentest engagement ref PE-2026-042, scope: 10.0.0.0/24
- Target environment: isolated lab network, no production systems
```

**Stories:**

```text
S1 — Port scan and service fingerprint (nmap wrapper)
     criteria: output/services.json exists with port/service/version fields

S2 — Enumerate HTTP endpoints and find login panels
     criteria: output/endpoints.txt lists discovered paths

S3 — Check for default credentials on discovered services
     criteria: output/findings.json populated, no plaintext passwords written to disk

S4 — Generate executive summary report in PDF
     criteria: output/report.pdf exists and is > 10KB
```

Ratchet enforces the no-credentials-on-disk rule via the security scan skill before every commit.

---

### Medical / Healthcare IT — FHIR API Integration

**Scenario:** Build a FHIR R4 patient data integration between two systems.

**company.md:**

```text
- Never log PHI to stdout or application logs
- All patient data encrypted at rest and in transit
- Audit log is append-only and tamper-evident
- FHIR version: R4, base URL: https://fhir.internal.hospital.org/r4
```

**Stories:**

```text
S1 — Implement FHIR Patient resource CRUD against upstream EHR
     criteria: GET /Patient/123 returns valid FHIR Bundle, POST creates resource

S2 — Add HL7 v2 to FHIR converter for lab results
     criteria: sample HL7 message converts to valid Observation resource

S3 — Implement audit logging for all PHI access (HIPAA requirement)
     criteria: every API call writes to audit.log with user, action, timestamp, patient ID

S4 — Encrypt PHI fields at rest using field-level encryption
     criteria: database dump shows encrypted values, decrypt function passes unit tests
```

---

### n8n / Workflow Automation — Build a Custom Node

**Scenario:** Build an n8n community node that wraps a custom internal API.

**Stories:**

```text
S1 — Scaffold n8n-nodes-myapi package with TypeScript boilerplate
     criteria: npm run build exits 0, node appears in n8n node list

S2 — Implement authentication (API key, stored in n8n credentials)
     criteria: credential type registered, test connection returns success

S3 — Add List, Get, Create, Update, Delete operations
     criteria: each operation has correct request/response mapping, unit tests pass

S4 — Publish to npm and write usage documentation
     criteria: npm publish succeeds, README has quickstart example
```

**verify.json:**

```json
{
  "custom_checks": [
    { "name": "TypeScript compiles", "command": "npm run build" },
    { "name": "tests pass",          "command": "npm test" },
    { "name": "package.json valid",  "command": "node -e \"require('./package.json')\"" }
  ]
}
```

---

### Data Engineering — Build an ETL Pipeline

**Scenario:** Ingest, transform, and load data from multiple sources into a data warehouse.

**Stories:**

```text
S1 — Ingest raw CSV files from S3 and validate schema
     criteria: ingestion script exits 0, invalid rows written to quarantine/

S2 — Transform: deduplicate, normalize dates, fill nulls per business rules
     criteria: output row count matches expected, no null primary keys

S3 — Load into BigQuery staging table
     criteria: bq show staging.events succeeds, row count matches transform output

S4 — Schedule via Airflow DAG (daily at 02:00 UTC)
     criteria: dag.py parses without error, schedule_interval == @daily
```

---

### Infrastructure as Code — Terraform Module

**Scenario:** Create a reusable Terraform module for a standard VPC layout.

**Stories:**

```text
S1 — Define VPC, subnets (public/private/data), route tables
     criteria: terraform validate passes, terraform plan shows expected resources

S2 — Add NAT gateway, Internet gateway, security groups
     criteria: no open 0.0.0.0/0 ingress rules except ports 80/443

S3 — Add outputs: VPC ID, subnet IDs, security group IDs
     criteria: all outputs declared, terraform-docs generates valid README

S4 — Write terratest integration test
     criteria: go test ./... exits 0 against a real AWS account (sandbox)
```

---

### SRE / Observability — Add Monitoring Stack

**Scenario:** Wire up Prometheus + Grafana for an existing service.

**Stories:**

```text
S1 — Add /metrics endpoint to the API (Prometheus format)
     criteria: curl localhost:8000/metrics returns # HELP lines

S2 — Deploy Prometheus with scrape config targeting the API
     criteria: Prometheus UI shows target as UP

S3 — Import Grafana dashboard with p50/p95/p99 latency panels
     criteria: dashboard JSON valid, panels visible via Grafana API

S4 — Configure alerting rule: error rate > 1% for 5 minutes
     criteria: alert rule YAML valid, alert appears in Prometheus rules list
```

**verify.json:**

```json
{
  "http_checks": [
    { "url": "http://localhost:8000/metrics",    "expected_status": 200 },
    { "url": "http://localhost:9090/-/healthy",  "expected_status": 200 },
    { "url": "http://localhost:3000/api/health", "expected_status": 200 }
  ],
  "docker_services": ["api", "prometheus", "grafana"]
}
```

---

## Tips for Writing Good Stories

1. **One verifiable outcome per story.** If you need two things, make two stories.
2. **Acceptance criteria are shell commands.** Phrase them so they map directly to `custom_checks`.
3. **Order by dependency.** Story S2 should never need something from S3.
4. **Front-load the foundation.** "Scaffold the package" before "add features to the package."
5. **Keep stories under ~2 hours of human work.** If it's bigger, split it.
6. **Use `verify.json` aggressively.** The tighter the acceptance gate, the less rework.

---

## Troubleshooting

**"No COMPLETE or BLOCKED signal"** — the agent ran but didn't follow the protocol. Check `logs/ratchet-TIMESTAMP.log`. The agent may need more context in `CLAUDE.md` or `.ratchet/company.md`.

**Story stays incomplete after multiple iterations** — run `./verify.sh` (or `.\verify.ps1`) manually to see which checks are failing. Check `.ratchet/progress.md` for recorded blockers.

**Agent refuses a security task** — add an `Authorization:` line to `.ratchet/company.md`. The orchestrator injects it into the trigger prompt automatically:

```text
- Authorization: I own example.com; full recon scope authorized
```

**`claude` not found** — install Claude Code CLI: `npm install -g @anthropic-ai/claude-code`, then authenticate: `claude auth`.

**PowerShell "not digitally signed"** — run once in an elevated session:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

**Python not found on Windows** — install from [python.org](https://www.python.org/downloads/) and check "Add Python to PATH" during setup.

---

## Extending Ratchet

### Add a Custom Skill

Create `skills/my-domain.md` with instructions for the agent, then reference it in `CLAUDE.md`:

```markdown
## Operating Protocol

...

5. Run skill if applicable:
   - My domain changes -> `skills/my-domain.md`
```

### Use a Different AI Tool

Pass `--tool codex` (bash) or `-Tool codex` (PowerShell) to swap the underlying AI tool. Anything that accepts `-p "prompt"` and outputs to stdout can be wired in.

### Chain Multiple Projects

Run Ratchet on project A, then project B in sequence from a wrapper script:

```bash
./ratchet.sh --project-dir /srv/project-a --max-iter 20
./ratchet.sh --project-dir /srv/project-b --max-iter 20
```

---

## Future Work

The items below are planned improvements. Contributions are welcome.

### Multi-LLM Support

Currently Ratchet calls whatever binary is passed via `--tool`. A proper multi-LLM adapter layer would let each story declare its preferred model, and Ratchet would handle the invocation differences automatically:

| Provider | CLI / API | Status |
| --- | --- | --- |
| Claude Code | `claude --dangerously-skip-permissions -p` | Supported today |
| OpenAI Codex / GPT-4o | `codex -p` / OpenAI API | Planned |
| DeepSeek Coder | `deepseek -p` / API | Planned |
| Gemini CLI | `gemini -p` | Planned |
| Ollama (local) | `ollama run <model> -p` | Planned |
| LM Studio (local) | OpenAI-compatible REST | Planned |

Story-level model selection in `prd.json`:

```json
{
  "id": "S1",
  "title": "Scaffold boilerplate",
  "model": "ollama/codellama",
  "acceptance_criteria": ["..."],
  "passes": false
}
```

Expensive stories (architecture, complex logic) use a frontier model. Cheap stories (boilerplate, formatting, docs) use a local or low-cost model. This can cut API cost by 60–80% on large PRDs.

---

### Web UI Dashboard

A real-time browser dashboard for monitoring loop progress:

- Story completion table with live updates
- Log streaming per iteration
- Add / reset stories without touching JSON
- BLOCKED reason display with retry button
- Built with FastAPI + HTMX (no JavaScript framework required)

---

### Parallel Story Execution

Run independent stories simultaneously in separate agent instances. Stories without `depends_on` relationships could be dispatched in parallel, reducing total wall-clock time significantly for large PRDs.

```json
{ "id": "S3", "depends_on": ["S1", "S2"], "title": "..." }
```

---

### Story Dependency Graph

Let stories declare explicit dependencies instead of relying on list order. Ratchet builds a DAG and executes in topological order, automatically parallelizing where possible.

---

### `ratchet doctor` — Preflight Check

A command that validates the environment before running:

```bash
./ratchet_state.py doctor
```

Checks: `claude` installed and authenticated, `prd.json` valid schema, `verify.json` endpoints reachable, git configured with user identity, required tools present (`docker`, `nginx`, `curl`).

---

### Slack / Webhook Notifications

Post to Slack (or any webhook) when a story completes, fails, or gets blocked. Useful for teams running overnight loops unattended.

```json
{ "webhook": "https://hooks.slack.com/services/...", "on": ["complete", "blocked"] }
```

---

### Auto-Retry Blocked Stories

A `--retry-blocked N` flag that re-attempts blocked stories up to N times before giving up, with the previous blocker message injected into the prompt for context.

---

### `ratchet rollback`

Undo the last story's commit if the output is incorrect:

```bash
./ratchet_state.py rollback
# git reverts last commit + resets story passes: false
```

---

### Token Usage Tracking

Log Claude API token consumption per iteration to `logs/usage.jsonl`. Surface estimated cost in `ratchet_state.py status`. Helps teams budget and optimize story sizing before committing to large runs.

---

### Audit Log

Append a structured entry to `audit.jsonl` for every iteration: story ID, timestamp, model used, pass/fail, token count, commit hash. Useful for compliance, retrospectives, and cost tracking across projects.

---

### Secret Scanning at Loop Level

Enforce secret detection as a hard gate in the orchestrator itself (not just the security skill). If the diff contains patterns matching API keys, tokens, or passwords, the loop aborts before committing regardless of what the agent decided.

---

### `pip install ratchet-loop` — Proper CLI Packaging

Package Ratchet as an installable Python CLI so teams can use it from any directory without path management:

```bash
pip install ratchet-loop
ratchet init --name "my-feature"
ratchet add-story
ratchet run --max-iter 20
ratchet status
```

---

## License

MIT — see [LICENSE](LICENSE).
