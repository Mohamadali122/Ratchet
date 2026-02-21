# PRD Generation Skill

Use this skill to create a structured PRD for a new Ratchet project. Guide the user through clarifying questions, then scaffold the state files.

## Process

### Step 1: Understand the Goal

Ask these questions (max 3, combine where possible):

1. What problem are you solving or what feature are you building?
2. What is the target environment? (e.g., Ubuntu + Docker Compose, specific services involved)
3. What does "done" look like — how will you verify it's working?

### Step 2: Break into Stories

Decompose the goal into 3–8 discrete stories. Each story must:

- Be completable in a single agent iteration
- Have clear, verifiable acceptance criteria (not vague goals)
- Be ordered by dependency — foundational work first

For each story, determine:
- What specifically needs to be built or changed?
- What are the exact acceptance criteria? (Commands that must pass, endpoints that must respond, etc.)
- Does this depend on a prior story?

### Step 3: Identify Verification Needs

Ask:
- Which HTTP endpoints should be health-checked after deploy?
- Which Docker Compose services must be in a healthy state?
- Is there a JWT/Keycloak token endpoint to validate?

### Step 4: Scaffold the PRD

Initialize the state directory:

```bash
./ratchet_state.py init --name "<kebab-case-feature-name>"
```

Add each story interactively:

```bash
./ratchet_state.py add-story
```

Create `.ratchet/verify.json` based on identified verification needs:

```json
{
  "http_checks": [
    { "url": "http://localhost/health", "expected_status": 200 }
  ],
  "docker_services": ["service-name"],
  "jwt_endpoint": "https://auth.example.com/realms/REALM/protocol/openid-connect/token"
}
```

### Step 5: Review Before Running

```bash
./ratchet_state.py status
```

Confirm with the user that all stories and acceptance criteria are correct before starting the loop.

## Story Quality Checklist

Before finalizing, verify each story has:

- [ ] An action-oriented title (starts with a verb: "Add", "Configure", "Deploy", "Fix")
- [ ] At least 2 specific, testable acceptance criteria
- [ ] No story depends on a story listed after it
- [ ] No acceptance criterion is vague (e.g., "works correctly" is not acceptable)
