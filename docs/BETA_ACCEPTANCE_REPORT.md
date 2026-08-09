# SecureWave Linux Beta 1 acceptance report

Date: 2026-08-09

## Result

- **Demo application:** PASS. Demo authentication and connect, disconnect, and
  reconnect are deterministic and make no HTTP or helper calls.
- **Portable ARM64 package:** PASS for Ubuntu 24.04 LTS ARM64 in an isolated
  systemd environment.
- **Public real-user beta:** BLOCKED. No authorized live backend account,
  Hetzner profile/peer registration, public egress, or publication evidence was
  available during this run.

This distinction is intentional: a local kernel WireGuard proof is not a
Hetzner or Internet-egress proof.

## Accepted artifact

- file: `securewave-vpn_4.0.0+8_arm64.deb`
- SHA-256: `f818a1423b1e93635135373e59578eebcf609652ca858164310ab83098c3835f`
- embedded source: `3bf69de36530d5d6c7da694da84854b8cfdc82e4`
- embedded source state: `clean`
- architecture: `arm64`
- helper contract: `13`
- publication state: `false`

Two consecutive builds from the embedded source produced the same package
SHA-256.

## Evidence

| Gate | Result | Evidence |
| --- | --- | --- |
| Focused backend structure/API tests | PASS | 6 tests passed |
| Flutter analysis and focused tests | PASS | no analysis issues; 5 tests passed |
| Demo network boundary | PASS | register, login, profile, status, connect, disconnect, reconnect, and logout performed zero HTTP requests |
| Clean package install | PASS | fresh Ubuntu 24.04 ARM64 container with systemd as PID 1 installed `4.0.0+8` without preinstalled GUI or VPN runtime packages |
| Runtime dependencies | PASS | GTK, libsecret, EGL, GLES, WireGuard, iproute2, iptables, and systemd dependencies resolved from package metadata |
| Helper installation | PASS | service enabled and active; socket present; packaged and installed helper/wrapper hashes matched; contract probe passed |
| GUI launch | PASS | packaged Flutter process remained alive for the 8-second headless X11 smoke window |
| Real kernel WireGuard lifecycle | PASS | two helper-driven handshakes completed against an isolated kernel peer; each cycle routed traffic and reported 476 received / 628 transmitted bytes |
| Disconnect and reconnect | PASS | both disconnects removed `sw-wg`, its runtime config, and owned IPv4/IPv6 firewall rules; the second connection re-established handshake and traffic |
| Package remove and purge | PASS | remove stopped and removed the helper/app while retaining Debian config state; purge removed the allowlist, config directory, and runtime group |
| Live backend account and PostgreSQL | BLOCKED | no authorized live account or target environment was supplied |
| Hetzner peer registration and public egress | BLOCKED | no authorized Hetzner/backend credentials or live profile were available |
| Public download | BLOCKED | the local manifest remains `published: false`; no deployment was performed |

## Isolation and cleanup

The install/runtime proof used a disposable privileged ARM64 Ubuntu container
with its own network namespace and a nested namespace for the WireGuard peer.
The host-installed SecureWave package was not changed. The test package was
removed and purged, and the disposable container was stopped and removed.

## Release decision

The repository is a working demo and an installable local beta candidate. It
must not be described as a completed public VPN beta until an authorized live
account obtains a profile from the intended backend, the client registers a
peer on the intended Hetzner server, public egress changes through that tunnel,
reconnect and restart succeed, cleanup is verified, and this exact artifact is
published.
