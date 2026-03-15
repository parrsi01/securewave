# TLS Hardening (Production)

This guide applies SecureWave's HTTPS-only production baseline with certbot on Hetzner.

## Files

- Nginx baseline template: `infra/nginx/securewave_prod.conf`
- TLS bootstrap script: `scripts/setup_tls_certbot.sh`

## Prerequisites

- Ubuntu/Debian host with public DNS record pointed at the server.
- Backend listening on `127.0.0.1:8080` (or override upstream host/port).
- Root access (`sudo`).

## Setup Steps

1. Set your domains and email:
   - `export DOMAIN=securewave.app`
   - `export WWW_DOMAIN=www.securewave.app`
   - `export EMAIL=ops@securewave.app`
2. Run TLS setup:
   - `sudo bash scripts/setup_tls_certbot.sh --domain "$DOMAIN" --domain "$WWW_DOMAIN" --email "$EMAIL" --upstream-host 127.0.0.1 --upstream-port 8080`
3. Validate HTTPS:
   - `curl -I "http://$DOMAIN"` should return `301` to `https://...`
   - `curl -I "https://$DOMAIN"` should return security headers including `Strict-Transport-Security`.

If you also expose an API hostname, add another `--domain api.securewave.app` so the certificate covers every public hostname in one issuance.

## Pre-DNS Readiness Check

Before the public DNS cutover, you can still verify the host-side HTTPS edge:

- `bash scripts/ops/check_https_edge_readiness.sh`

This validates:
- `securewave-api` is healthy on `127.0.0.1:8080`
- `nginx` is active and its config passes `nginx -t`
- the local HTTP and HTTPS edge paths proxy `/api/health` successfully
- `certbot.timer` is installed, enabled, and active when present

## Renewal Verification

- Certbot timer status:
  - `sudo systemctl status certbot.timer`
- Dry-run renewal:
  - `sudo certbot renew --dry-run`
- Nginx reload hook:
  - `/etc/letsencrypt/renewal-hooks/deploy/securewave_nginx_reload.sh`

## Security Baseline Included

- HTTP -> HTTPS redirect.
- TLS 1.2/1.3 only.
- Strong TLS cipher baseline.
- OCSP stapling enabled.
- `server_tokens off`.
- HSTS (`max-age=63072000; includeSubDomains; preload`).
- `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`, and strict CSP.
- Forwarded proto forced to `https` upstream.

## Troubleshooting

- Cert issuance fails:
  - Confirm DNS resolves to server IP.
  - Confirm ports `80` and `443` are open in both UFW and the Hetzner firewall.
  - Verify challenge path:
    - `curl -i "http://$DOMAIN/.well-known/acme-challenge/test"`
- `nginx -t` fails:
  - Confirm cert files exist under `/etc/letsencrypt/live/<domain>/`.
  - Confirm template placeholders are rendered in deployed config.
- Renewal fails:
  - Run `sudo certbot renew --dry-run` and inspect `/var/log/letsencrypt/letsencrypt.log`.
