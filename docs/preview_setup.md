# Preview Setup (No Domain Required)

This guide lets you run the SecureWave website locally or on a Hetzner staging server **without buying a domain**.

Supported access patterns:
- Local: `http://localhost:8080`
- Staging (public IP): `http://<PUBLIC_IP>.nip.io` and `https://<PUBLIC_IP>.nip.io` (if SSL enabled)

## What Runs Where

- SecureWave app (FastAPI) serves:
  - Marketing pages and static assets from `static/`
  - API under `/api/*`
- Nginx (optional locally, recommended on staging) terminates TLS and proxies to the app port.

Default ports:
- App: `127.0.0.1:8080`
- Nginx staging: `80/443` (public)

## Local Run (No Root)

1. Start the app:
```bash
./start_site.sh
```

2. Open:
- `http://localhost:8080/`
- `http://localhost:8080/api/health`
- `http://localhost:8080/api/docs` (if enabled)

Stop:
```bash
./stop_site.sh
```

## Staging Run (Hetzner, Public IP + nip.io)

1. SSH to the server, clone the repo, and from the repo root run:
```bash
sudo LETSENCRYPT_EMAIL=ops@example.com ./setup_preview.sh
```

This will:
- Install Nginx (+ certbot if configured)
- Configure an IP-based preview host via nip.io:
  - `http://<PUBLIC_IP>.nip.io`
- Attempt Let's Encrypt (HTTP-01 via `/.well-known/acme-challenge/`) when possible
- Open firewall ports (UFW if present)

2. Start the app (as the `securewave` user is fine):
```bash
./start_site.sh
```

3. Print preview URLs:
```bash
./preview_info.sh
```

4. Open in your browser:
- `http://<PUBLIC_IP>.nip.io/`
- `https://<PUBLIC_IP>.nip.io/` (if SSL succeeded)

Stop:
```bash
./stop_site.sh
```

## SSL Modes

Control with `PREVIEW_SSL_MODE`:
- `auto` (default): attempts Let's Encrypt only if `LETSENCRYPT_EMAIL` is set and host is public.
- `letsencrypt`: force Let's Encrypt (requires `LETSENCRYPT_EMAIL`).
- `selfsigned`: generate a short-lived self-signed cert (OK for local dev; browsers will warn).
- `none`: HTTP only.

Examples:
```bash
sudo PREVIEW_SSL_MODE=selfsigned ./setup_preview.sh
sudo PREVIEW_SSL_MODE=letsencrypt LETSENCRYPT_EMAIL=ops@example.com ./setup_preview.sh
```

## Example Preview URLs (nip.io)

If your staging IP is `138.199.204.139`, then:
- `http://138.199.204.139.nip.io/` should return **200** with the marketing homepage.
- `http://138.199.204.139.nip.io/api/health` should return **200** JSON.
- `https://138.199.204.139.nip.io/` should work if Let's Encrypt succeeded (or self-signed is enabled).

## Verification Checklist

Run these from your laptop:
```bash
curl -i http://<PUBLIC_IP>.nip.io/ | head
curl -i http://<PUBLIC_IP>.nip.io/css/site.css | head
curl -i http://<PUBLIC_IP>.nip.io/js/site.js | head
curl -i http://<PUBLIC_IP>.nip.io/api/health
```

