# Authentication and Security Implementation

## Secrets

Secrets are read from environment variables only. The application does not integrate with external secrets managers.

## Authentication

- JWT access/refresh tokens
- Password hashing and validation
- Role-based admin endpoints

## Transport Security

- Use HTTPS via a reverse proxy
- Keep SSH and WireGuard ports only by default

## Operational Security

- Host hardening via `scripts/hetzner_bootstrap.sh`
- Fail2ban enabled
