# nginx Test Skill

Run this skill after any nginx configuration change. Validates config syntax, proxy routing, and security headers.

## Steps

### 1. Validate Config Syntax

This must pass before any reload or deploy:

```bash
nginx -t
```

If this fails: stop immediately, report `nginx config INVALID`, do not proceed.

### 2. Check nginx is Running

```bash
if command -v systemctl >/dev/null 2>&1; then
  systemctl is-active nginx 2>/dev/null || true
else
  docker compose ps nginx 2>/dev/null | grep -iE "running|healthy" || true
fi
```

### 3. Test Reverse Proxy Routing

```bash
# Should not return 502 Bad Gateway (upstream unreachable)
status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://localhost/")
echo "Root → $status"

# Check for 502 indicating upstream is down
if [[ "$status" == "502" ]]; then
  echo "ERROR: nginx returned 502 — upstream service unreachable"
fi
```

### 4. Verify Security Headers

```bash
curl -sI "http://localhost/" | grep -E \
  "X-Frame-Options|X-Content-Type-Options|Strict-Transport-Security|Content-Security-Policy" || true
```

Expected headers for production:
- `X-Frame-Options: SAMEORIGIN` or `DENY`
- `X-Content-Type-Options: nosniff`
- `Strict-Transport-Security` (HTTPS only)

### 5. Check SSL/TLS (if HTTPS configured)

```bash
if [[ -n "${PRIMARY_DOMAIN:-}" ]]; then
  echo | openssl s_client -connect "${PRIMARY_DOMAIN}:443" -brief 2>&1 | head -5 || true
fi
```

## Reporting

- `nginx -t` fails → `nginx config INVALID: <error>` — STOP, do not deploy
- Proxy returns 502 → `nginx routing FAILED: upstream unreachable`
- Missing security headers → `WARNING: security header missing: <header>`
- All pass → `nginx validation PASSED`
