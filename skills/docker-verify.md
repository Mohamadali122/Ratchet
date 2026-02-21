# Docker Verify Skill

Run this skill after any Docker Compose change to confirm all services are healthy post-deploy.

## Steps

### 1. List Current Service States

```bash
docker compose ps
```

### 2. Check for Unhealthy or Stopped Services

```bash
docker compose ps --format json | python3 -c "
import json, sys
issues = []
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        s = json.loads(line)
        state = s.get('Health', s.get('State', 'unknown'))
        name = s.get('Service', s.get('Name', '?'))
        if state not in ('healthy', 'running'):
            issues.append(f'{name}: {state}')
    except (json.JSONDecodeError, KeyError):
        pass
if issues:
    print('UNHEALTHY:', ', '.join(issues))
    sys.exit(1)
else:
    print('All services healthy')
"
```

### 3. Check Recent Logs for Errors

```bash
docker compose logs --tail=50 2>&1 | grep -iE "error|fatal|panic|exception" | head -20 || true
```

### 4. Check Restart Counts

Services that have restarted more than 3 times indicate a crash loop:

```bash
docker compose ps --format json | python3 -c "
import json, sys
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        s = json.loads(line)
        restarts = s.get('Restarts', 0)
        name = s.get('Service', s.get('Name', '?'))
        if isinstance(restarts, int) and restarts > 3:
            print(f'WARNING: {name} restarted {restarts} times')
    except (json.JSONDecodeError, KeyError):
        pass
"
```

## Reporting

- All healthy → `Docker verification PASSED`
- Any unhealthy service → `Docker verification FAILED: <service>: <state>` then exit 1
- Crash loop detected → investigate logs before proceeding
