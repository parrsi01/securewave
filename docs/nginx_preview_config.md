# Nginx Preview Config

SecureWave's preview Nginx template is:
- `nginx/securewave_preview.conf`

`setup_preview.sh` renders this template into:
- `/etc/nginx/sites-available/securewave_preview.conf`
- `/etc/nginx/sites-enabled/securewave_preview.conf`

## Design Goals

- No domain required: use `nip.io` hostnames like `138.199.204.139.nip.io`.
- Keep upstream private: proxy to `127.0.0.1:8080` by default.
- Support HTTPS:
  - Let's Encrypt on public staging (HTTP-01 webroot challenge)
  - Self-signed fallback for local/dev

## Key Sections

### Upstream

The template defines:
- `upstream securewave_preview_upstream { server 127.0.0.1:8080; }`

This points Nginx at the FastAPI app which serves:
- `/` marketing pages from `static/`
- `/api/*` backend endpoints

### ACME Challenge

The `/.well-known/acme-challenge/` location is served from:
- `/var/www/securewave_acme`

This enables certbot `--webroot` issuance without needing a domain.

### Proxy Headers

The config sets:
- `Host`
- `X-Forwarded-Proto`
- `X-Real-IP`
- `X-Forwarded-For`

These are required for correct request context on the backend (logging, auth, redirects).

## Rendering / Placeholder Substitution

Placeholders in the template:
- `__SERVER_NAME__` -> `PREVIEW_HOST` or `<PUBLIC_IP>.nip.io`
- `__UPSTREAM_HOST__` -> `PREVIEW_UPSTREAM_HOST` (default `127.0.0.1`)
- `__UPSTREAM_PORT__` -> `PREVIEW_UPSTREAM_PORT` (default `8080`)
- `__SSL_CERT__`, `__SSL_KEY__` -> cert paths when SSL enabled

When SSL is disabled, `setup_preview.sh` removes the SSL server block delimited by:
- `# SSL_BLOCK_BEGIN`
- `# SSL_BLOCK_END`

## Troubleshooting

- `nginx -t` fails:
  - Check that the rendered config exists at `/etc/nginx/sites-available/securewave_preview.conf`.
  - Check file permissions on certificate paths.

- Let's Encrypt fails:
  - Confirm `PREVIEW_HOST` resolves to the server IP: `dig +short <IP>.nip.io`
  - Confirm ports `80` and `443` are open on the server firewall and Hetzner firewall.
  - Check Nginx is serving the ACME path:
    - `curl -i http://<IP>.nip.io/.well-known/acme-challenge/test`

