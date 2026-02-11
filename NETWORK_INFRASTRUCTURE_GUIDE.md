# Network Infrastructure Guide

## Overview

SecureWave runs on a single Hetzner Cloud server with explicit firewall rules.

## Firewall

- SSH: `tcp/22`
- WireGuard: `udp/51820`

HTTP/HTTPS are closed by default. To open them, set `allow_http_https = true` in Terraform and re-apply.

## DDoS and Rate Limiting

- Use application-level rate limiting and WireGuard peer limits.
- Consider adding a CDN or external WAF only when explicitly approved.

## Monitoring

- OS metrics via standard Linux tooling
- Application logs via Docker or systemd
