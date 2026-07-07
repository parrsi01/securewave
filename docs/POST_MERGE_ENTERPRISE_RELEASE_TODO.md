# Post-Merge Enterprise Release TODO

Use this checklist after the Linux enterprise VPN certification work from PR #15 is merged. Do not treat an item as complete without a command, artifact, or operator note that can be reviewed later.

## Release Checklist

- [ ] Production Compose validation: on the authorized production host, run `docker compose --env-file .env -f deploy/hetzner/compose.yaml config --quiet` with the reviewed image tag and record redacted pass/fail evidence.
- [ ] Hetzner fleet audit: with `HETZNER_API_TOKEN` set, run `python3 infrastructure/hetzner/audit_vpn_fleet.py --json-out artifacts/post-merge-enterprise-release/hetzner-fleet-audit.json`; do not include token values in logs or artifacts.
- [ ] Authorized external load test: run the approved load plan only against SecureWave-owned infrastructure, including WireGuard/OpenVPN/IKEv2 profile fetches and usage reporting, and record p95/p99 latency plus error rate.
- [ ] x64 Linux `.deb` publication: build the signed x64 Linux package, publish it to the release/download location, and verify install, launch, helper service registration, connect, disconnect, and uninstall on a clean x64 Linux VM.
- [ ] Public download manifest verification: fetch the public manifest and every referenced Linux artifact URL, verify checksums and MIME types, and confirm no stale branch, local, or placeholder URLs remain.
- [ ] Protocol documentation truth update: update `README.md`, `docs/current_release_status.md`, and user-facing protocol docs so WireGuard/OpenVPN/IKEv2 claims match the final production evidence.
- [ ] Monitoring and alerting requirements: configure health, login, profile issuance, VPN usage reporting, container, database, Redis, disk, CPU, memory, and protocol-specific failure alerts with named owners and escalation paths.
- [ ] Support/debug runbook: publish a user-support runbook covering install logs, helper status, WireGuard/OpenVPN/IKEv2 diagnostics, DNS/routing checks, usage-metering checks, redaction rules, and escalation bundles.

## Required Closeout Evidence

- Commit SHA and image digest released.
- Redacted Compose validation output.
- Redacted Hetzner fleet audit summary.
- External load-test summary and approval record.
- Linux `.deb` URL, checksum, install proof, and uninstall proof.
- Download manifest URL and checksum verification output.
- Links to updated protocol truth docs.
- Monitoring dashboard and alert policy links.
- Support/debug runbook link.
