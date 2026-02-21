# API Test Skill

Run this skill after any API or authentication endpoint change. Validates HTTP responses with and without JWT auth.

## Steps

### 1. Load Endpoint Config

```bash
python3 -c "
import json
with open('.ratchet/verify.json') as f:
    v = json.load(f)
print(json.dumps(v.get('http_checks', []), indent=2))
"
```

### 2. Obtain JWT Token (if jwt_endpoint configured)

Uses environment variables for credentials — never hardcode these:

```bash
JWT_ENDPOINT=$(python3 -c "
import json
with open('.ratchet/verify.json') as f:
    v = json.load(f)
print(v.get('jwt_endpoint', ''))
")

if [[ -n "$JWT_ENDPOINT" ]]; then
  TOKEN=$(curl -s -X POST "$JWT_ENDPOINT" \
    -d "grant_type=client_credentials" \
    -d "client_id=${RATCHET_CLIENT_ID:-}" \
    -d "client_secret=${RATCHET_CLIENT_SECRET:-}" \
    | python3 -c "import json,sys; print(json.load(sys.stdin).get('access_token',''))")
  echo "Token obtained: ${TOKEN:0:20}..."
fi
```

Required environment variables: `RATCHET_CLIENT_ID`, `RATCHET_CLIENT_SECRET`

### 3. Test Each Configured Endpoint

```bash
curl -s -o /dev/null -w "%{http_code} %{url_effective}\n" \
  -H "Authorization: Bearer ${TOKEN:-}" \
  --max-time 15 \
  "$URL"
```

### 4. Verify Unauthenticated Access Returns 401

For protected endpoints, confirm they reject requests without a token:

```bash
curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$PROTECTED_URL"
# Must return 401, not 200
```

## Reporting

For each endpoint: `[STATUS] URL (expected: NNN)`

- All pass → `API tests PASSED`
- Any unexpected status → `API test FAILED: <url> returned <actual>, expected <expected>`
- Protected endpoint returns 200 without auth → `CRITICAL: unauthenticated access on <url>`
