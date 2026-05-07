# Internal Launch Talking Points

## Core Message

SecureWave is launching a Linux desktop free release candidate first. The public v1 scope is intentionally narrow: Linux desktop, WireGuard primary, free mode now, Premium coming soon.

## Evidence Anchors

- `docs/current_release_status.md` defines the canonical v1 release truth.
- `securewave_app/LINUX_VPN_SETUP.md` documents the Linux `wg-quick` WireGuard runtime path.
- `docs/guides/DESKTOP_THREE_PROTOCOL_PLAN.md` states broader desktop multi-protocol work is post-v1 backlog and must not broaden public v1 support claims.
- `routes/downloads.py` and `docs/current_release_status.md` reference Linux release/download verification paths.

## Answers To Obvious Questions

**Is SecureWave available for Windows, macOS, iOS, or Android?**

Not as public v1 VPN runtime support. Those platforms may have code, setup notes, stubs, or backlog plans in the repository, but they are not part of the Linux free release-candidate announcement.

**Which VPN protocol is public v1?**

WireGuard is the primary Linux public v1 protocol.

**Is OpenVPN supported?**

Do not promote OpenVPN broadly. The truthful boundary is that OpenVPN is limited to the already certified covered Linux runtime/helper dataplane path unless it is separately promoted later through normal backend and Linux client-path certification.

**Is IKEv2 part of the release?**

No. IKEv2 is not public v1 release-visible. It remains experimental/manual or hidden unless provisioning and security hardening are completed and the release decision is reopened.

**Is SecureWave free?**

The current public release-candidate message is free mode now. Premium is coming soon, but paid production billing should not be presented as live unless separately promoted with current evidence.

**Can we say SecureWave is production scale?**

No. Do not claim scale, fleet size, enterprise readiness, or mature SaaS operations beyond the current proof. Say Linux desktop free release candidate and describe the validated capabilities.

**Can we mention security?**

Yes, but keep it concrete. It is acceptable to say SecureWave uses WireGuard on Linux and includes authenticated profile retrieval, artifact verification, and protocol readiness checks. Do not claim anonymity, guaranteed privacy, or unsupported threat-model outcomes.

## Launch-Safe Phrases

- "Linux desktop free release candidate."
- "WireGuard-primary Linux VPN experience."
- "Available for release-candidate testing on Linux."
- "Premium coming soon."
- "Additional platforms and protocols remain gated by validation."

## Phrases To Avoid

- "Available on all platforms."
- "Windows/macOS/mobile ready."
- "Full WireGuard, OpenVPN, and IKEv2 support."
- "Paid subscriptions are live."
- "Enterprise-scale VPN SaaS."
- "Anonymous VPN" or "guaranteed privacy."

## Defensive Position

If challenged on scope, answer directly: SecureWave is deliberately launching with the strongest current evidence first. Linux/WireGuard is the public release-candidate path. OpenVPN and IKEv2 are not being over-promoted, and non-Linux runtime support remains outside the public v1 claim until validated.
