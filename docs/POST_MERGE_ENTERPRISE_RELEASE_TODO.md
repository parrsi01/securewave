# Post-Merge Enterprise Release TODO

Use this checklist after the Linux enterprise VPN certification work from PR #15 is merged. Do not treat an item as complete without a command, artifact, or operator note that can be reviewed later.

For the cross-platform portable release gate, use
`docs/PORTABLE_RELEASE_CLOSEOUT_PLAN.md` as the authoritative closeout plan
before marking Linux ARM64/x64, Windows, or macOS artifacts available.

## Release Checklist

Local pre-release evidence on 2026-07-15 completed the ARM64 package lifecycle,
contract-13 verifier, isolated IKEv2 lab, disposable PostgreSQL concurrency,
Flutter/Linux build, Docker/Compose syntax/build, and repository/security
checks. Production Compose, Hetzner fleet, and public ARM64 publication
evidence were added on 2026-07-26. External load testing, fresh final-package
tunnel proof, monitoring ownership, x86-64 publication, and repository-wide
Ruff baseline findings remain separate work.

- [x] Production Compose validation: completed 2026-07-26 on
  `securewave-prod` with the protected production environment file and a
  reviewed commit-tag-shaped placeholder image reference. `docker compose
  config --quiet` passed; no image was pulled and no service was changed.
- [x] Hetzner fleet audit: completed 2026-07-26 through the authenticated
  `hcloud` context without copying or printing a token. Production, staging API,
  and staging WireGuard had attached firewalls; the separate test-client host
  did not.
- [ ] Authorized external load test: run the approved load plan only against SecureWave-owned infrastructure, including WireGuard/OpenVPN/IKEv2 profile fetches and usage reporting, and record p95/p99 latency plus error rate.
- [ ] x64 Linux `.deb` publication: build the signed x64 Linux package, publish it to the release/download location, and verify install, launch, helper service registration, connect, disconnect, and uninstall on a clean x64 Linux VM.
- [x] Public download manifest verification: completed 2026-07-26. The public
  manifest exposes macOS and Windows as `coming_soon` plus the verified Linux
  ARM64 package; the two obsolete Linux archive URLs return 404 and the public
  package SHA-256 matches the manifest.
- [x] Protocol documentation truth update: `README.md` and
  `docs/current_release_status.md` identify WireGuard as the only public Linux
  v1 protocol and keep OpenVPN/IKEv2 fail-closed.
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
