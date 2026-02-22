# Keycloak Verify Skill

Run this skill after any Keycloak realm, client, or SSO configuration change.
Validates realm existence, client credentials flow, token contents, and role mappings.

## Prerequisites

Required environment variables:
- `KEYCLOAK_URL` — base URL, e.g. `https://auth.example.com`
- `KEYCLOAK_REALM` — realm name, e.g. `myrealm`
- `RATCHET_CLIENT_ID` — client ID for client credentials grant
- `RATCHET_CLIENT_SECRET` — client secret

Optional:
- `KEYCLOAK_ADMIN_USER` / `KEYCLOAK_ADMIN_PASS` — for admin API checks
- `KEYCLOAK_EXPECTED_ROLES` — comma-separated roles the token must contain

## Steps

### 1. Check Keycloak is Reachable

```bash
KEYCLOAK_URL="${KEYCLOAK_URL:-http://localhost:8080}"
status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
  "${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM:-master}/.well-known/openid-configuration")
echo "Keycloak discovery endpoint: $status"
if [[ "$status" != "200" ]]; then
  echo "CRITICAL: Keycloak unreachable or realm missing — got HTTP $status"
  exit 1
fi
```

### 2. Obtain Token via Client Credentials

```bash
TOKEN_RESPONSE=$(curl -s -X POST \
  "${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=${RATCHET_CLIENT_ID}" \
  -d "client_secret=${RATCHET_CLIENT_SECRET}" \
  --max-time 15)

echo "$TOKEN_RESPONSE" | python3 -c "
import json, sys
resp = json.load(sys.stdin)
if 'access_token' not in resp:
    print(f'CRITICAL: token request failed — {resp.get(\"error\", \"unknown\")} : {resp.get(\"error_description\", \"\")}')
    sys.exit(1)
token = resp['access_token']
print(f'Token obtained: {token[:30]}...')
print(f'Expires in: {resp.get(\"expires_in\", \"?\")}s')
print(f'Token type: {resp.get(\"token_type\", \"?\")}')
"
```

### 3. Decode and Inspect Token Claims

```bash
ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('access_token',''))")

python3 -c "
import base64, json, sys
token = sys.argv[1]
parts = token.split('.')
if len(parts) != 3:
    print('CRITICAL: token is not a valid JWT (expected 3 parts)')
    sys.exit(1)

# Decode payload (add padding as needed)
payload_b64 = parts[1] + '=' * (4 - len(parts[1]) % 4)
try:
    payload = json.loads(base64.urlsafe_b64decode(payload_b64))
except Exception as e:
    print(f'CRITICAL: cannot decode token payload — {e}')
    sys.exit(1)

import datetime
exp = payload.get('exp', 0)
now = datetime.datetime.utcnow().timestamp()
remaining = exp - now

print(f'Issuer:    {payload.get(\"iss\", \"?\")}')
print(f'Subject:   {payload.get(\"sub\", \"?\")}')
print(f'Client ID: {payload.get(\"azp\", payload.get(\"client_id\", \"?\"))}')
print(f'Expires:   {remaining:.0f}s from now')

if remaining <= 0:
    print('CRITICAL: token is already expired')
    sys.exit(1)
elif remaining < 30:
    print('WARNING: token expires in under 30 seconds')

roles = (payload.get('realm_access') or {}).get('roles', [])
print(f'Realm roles: {roles}')

resource_access = payload.get('resource_access', {})
for client, data in resource_access.items():
    print(f'Client roles [{client}]: {data.get(\"roles\", [])}')
" "$ACCESS_TOKEN"
```

### 4. Validate Expected Roles (if configured)

```bash
if [[ -n "${KEYCLOAK_EXPECTED_ROLES:-}" ]]; then
  python3 -c "
import base64, json, sys
token = sys.argv[1]
expected = [r.strip() for r in sys.argv[2].split(',')]
parts = token.split('.')
payload_b64 = parts[1] + '=' * (4 - len(parts[1]) % 4)
payload = json.loads(base64.urlsafe_b64decode(payload_b64))
realm_roles = (payload.get('realm_access') or {}).get('roles', [])
missing = [r for r in expected if r not in realm_roles]
if missing:
    print(f'CRITICAL: token missing expected roles: {missing}')
    sys.exit(1)
else:
    print(f'All expected roles present: {expected}')
" "$ACCESS_TOKEN" "${KEYCLOAK_EXPECTED_ROLES}"
fi
```

### 5. Verify Token Works on Protected Endpoint

If `http_checks` are configured in `.ratchet/verify.json`, test at least one with the token:

```bash
python3 -c "
import json
with open('.ratchet/verify.json') as f:
    v = json.load(f)
checks = v.get('http_checks', [])
if checks:
    print(checks[0]['url'])
" | xargs -I{} curl -s -o /dev/null -w "Protected endpoint %{url_effective}: %{http_code}\n" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" --max-time 15 {} || true
```

### 6. Admin API Check (optional — only if admin credentials set)

```bash
if [[ -n "${KEYCLOAK_ADMIN_USER:-}" && -n "${KEYCLOAK_ADMIN_PASS:-}" ]]; then
  ADMIN_TOKEN=$(curl -s -X POST \
    "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
    -d "grant_type=password" \
    -d "client_id=admin-cli" \
    -d "username=${KEYCLOAK_ADMIN_USER}" \
    -d "password=${KEYCLOAK_ADMIN_PASS}" \
    | python3 -c "import json,sys; print(json.load(sys.stdin).get('access_token',''))")

  # Check realm exists
  realm_status=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}")
  echo "Realm ${KEYCLOAK_REALM} admin check: $realm_status"
fi
```

## Reporting

- Keycloak unreachable → `CRITICAL: Keycloak unreachable at <url>` — stop, exit 1
- Token request fails → `CRITICAL: client credentials rejected — <error>` — stop, exit 1
- Token expired → `CRITICAL: token expired`
- Missing roles → `CRITICAL: token missing expected roles: [<roles>]`
- All pass → `Keycloak verification PASSED — token valid, roles confirmed`
