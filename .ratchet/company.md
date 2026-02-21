# Company Context

## Org Standards

- Git convention: conventional commits (`feat(scope):`, `fix(scope):`, `chore:`)
- Never hardcode secrets -- use environment variables or a secrets manager
- All API keys and tokens must be loaded from environment at runtime
- Output directory for generated files: `output/` (gitignored)
- Python style: type hints throughout, async for I/O-bound work, argparse for CLIs
- Dependencies managed via `requirements.txt`

## Infrastructure Conventions

- Container orchestration: Docker Compose
- Reverse proxy: nginx
- Auth: Keycloak SSO with JWT (OIDC)
- Primary domain: example.com
- Docker network: app-net

## Authorization

<!-- Uncomment and customize for security/recon work:
- Authorization: I own example.com; full recon scope authorized
-->
