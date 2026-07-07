# Protocol documentation truth scan

## IKEv2 disabled claims
README.md:7:profile, and IKEv2 is disabled in the Linux release UI until the backend and
docs/hr_app_process_overview/README.md:39:- IKEv2 is disabled in the Linux release app until strongSwan profile import,
docs/current_release_status.md:7:profile and the Linux helper confirms startup. IKEv2 is disabled in the Linux
docs/current_release_status.md:37:- IKEv2 is blocked in the Linux client until native strongSwan
docs/current_release_status.md:92:- IKEv2 remains unavailable for public Linux release until profile provisioning,
docs/current_release_status.md:97:- IKEv2 may be kept experimental/manual outside the Linux release app unless
docs/guides/DESKTOP_THREE_PROTOCOL_PLAN.md:9:normal backend/client-path certification; IKEv2 is experimental/manual or hidden
docs/guides/DESKTOP_THREE_PROTOCOL_PLAN.md:71:  - Misconfigured `OpenVPN` and `IKEv2` remain blocked with specific error codes.

## OpenVPN blocked/limited claims
docs/guides/DESKTOP_THREE_PROTOCOL_PLAN.md:7:desktop first with WireGuard primary; OpenVPN is limited to the already
docs/guides/DESKTOP_THREE_PROTOCOL_PLAN.md:20:- Treat `OpenVPN` as the compatibility and restrictive-network fallback.
docs/guides/DESKTOP_THREE_PROTOCOL_PLAN.md:28:  - `OpenVPN` for blocked/restrictive networks, TCP fallback, and legacy compatibility
docs/guides/DESKTOP_THREE_PROTOCOL_PLAN.md:52:  - Use `OpenVPN` as the first general fallback if `WireGuard` is unavailable.
docs/guides/DESKTOP_THREE_PROTOCOL_PLAN.md:71:  - Misconfigured `OpenVPN` and `IKEv2` remain blocked with specific error codes.
docs/guides/DESKTOP_THREE_PROTOCOL_PLAN.md:82:- `OpenVPN` and `IKEv2` are strategic fallbacks, not equal defaults.

## WireGuard-only or primary runtime claims
README.md:5:Current app truth is Linux desktop first. WireGuard is the strongest verified
docs/current_release_status.md:5:SecureWave is currently a Linux desktop first app. WireGuard is the primary
docs/POST_MERGE_ENTERPRISE_RELEASE_TODO.md:9:- [ ] Authorized external load test: run the approved load plan only against SecureWave-owned infrastructure, including WireGuard/OpenVPN/IKEv2 profile fetches and usage reporting, and record p95/p99 latency plus error rate.
securewave_app/DEBUG_CHECKLIST.md:30:- WireGuard is only connected after `wg-quick up` returns successfully and
securewave_app/DEBUG_CHECKLIST.md:32:- WireGuard disconnect is only clean after interface `securewave` is gone.
docs/guides/DESKTOP_THREE_PROTOCOL_PLAN.md:7:desktop first with WireGuard primary; OpenVPN is limited to the already
docs/guides/DESKTOP_THREE_PROTOCOL_PLAN.md:19:- Keep `WireGuard` as the default protocol everywhere for speed, stability, privacy, and live-stream resilience.
docs/guides/DESKTOP_THREE_PROTOCOL_PLAN.md:81:- `WireGuard` remains the only recommended default for streaming stability, privacy, and speed.

## helper/pkexec/sudo wording
README.md:6:runtime path, OpenVPN has a Linux helper path when the backend issues a real
README.md:8:strongSwan runtime are enabled end to end. The Flutter client must never mark a
README.md:13:Packet Tunnel Provider entitlement scope, not Hotspot Helper. Final signed
README.md:33:- **Networking and VPN operations:** WireGuard profile generation and peer lifecycle management, plus multiprotocol provisioning and validation paths for OpenVPN and IKEv2
README.md:43:- **VPN/Infra:** WireGuard, OpenVPN/IKEv2 support code, Terraform, Docker, systemd, Nginx
docs/APPLE_REVIEW_HANDOFF.md:16:SecureWave does not use Hotspot Helper. It does not scan, classify,
docs/VERIFICATION_COMMANDS.md:71:# Verify wg-quick integration exists
docs/VERIFICATION_COMMANDS.md:72:grep -n "wg-quick" securewave_app/linux/runner/my_application.cc && echo "OK: wg-quick integration found"
docs/APP_STORE_REVIEW_NOTES.md:19:- SecureWave does not use Hotspot Helper and does not authenticate captive Wi-Fi networks.
docs/hr_app_process_overview/README.md:37:- WireGuard uses `wg-quick`.
docs/hr_app_process_overview/README.md:38:- OpenVPN uses `openvpn`.
docs/hr_app_process_overview/README.md:39:- IKEv2 is disabled in the Linux release app until strongSwan profile import,
docs/runtime_process_cleanup.md:26:## VPN Helper Checks
docs/runtime_process_cleanup.md:29:which wg-quick openvpn swanctl ipsec pkexec || true
docs/runtime_process_cleanup.md:31:pgrep -af 'securewave-openvpn|securewave.ovpn' || true
docs/runtime_process_cleanup.md:34:Do not kill a system OpenVPN or WireGuard server process unless it is clearly a
docs/runtime_process_cleanup.md:47:and usage state, lists servers, and requests WireGuard/OpenVPN/IKEv2 profiles.
docs/runtime_process_cleanup.md:49:non-200 WireGuard or OpenVPN profile result as a release blocker. IKEv2 may
docs/runtime_process_cleanup.md:50:still return a typed non-200 until the Linux strongSwan path is implemented.
docs/current_release_status.md:6:runtime path. OpenVPN is enabled only when the backend issues a real OpenVPN
docs/current_release_status.md:7:profile and the Linux helper confirms startup. IKEv2 is disabled in the Linux
docs/current_release_status.md:8:release UI until the backend returns a Linux IKEv2 profile and strongSwan
docs/current_release_status.md:35:- OpenVPN profile issuance works on the live API for the verified Hetzner node;
docs/current_release_status.md:36:  full app connect still depends on local OpenVPN installation and privileges.
docs/current_release_status.md:37:- IKEv2 is blocked in the Linux client until native strongSwan
docs/current_release_status.md:52:  Hotspot Helper.
docs/current_release_status.md:93:  strongSwan start/status verification, and cleanup are proven.
docs/current_release_status.md:108:- Mobile OpenVPN/IKEv2 expansion after platform-specific evidence exists.
docs/current_release_status.md:125:- Do not expose OpenVPN or IKEv2 as default-visible release protocols unless
docs/POST_MERGE_ENTERPRISE_RELEASE_TODO.md:9:- [ ] Authorized external load test: run the approved load plan only against SecureWave-owned infrastructure, including WireGuard/OpenVPN/IKEv2 profile fetches and usage reporting, and record p95/p99 latency plus error rate.
docs/POST_MERGE_ENTERPRISE_RELEASE_TODO.md:10:- [ ] x64 Linux `.deb` publication: build the signed x64 Linux package, publish it to the release/download location, and verify install, launch, helper service registration, connect, disconnect, and uninstall on a clean x64 Linux VM.
docs/POST_MERGE_ENTERPRISE_RELEASE_TODO.md:12:- [ ] Protocol documentation truth update: update `README.md`, `docs/current_release_status.md`, and user-facing protocol docs so WireGuard/OpenVPN/IKEv2 claims match the final production evidence.
docs/POST_MERGE_ENTERPRISE_RELEASE_TODO.md:14:- [ ] Support/debug runbook: publish a user-support runbook covering install logs, helper status, WireGuard/OpenVPN/IKEv2 diagnostics, DNS/routing checks, usage-metering checks, redaction rules, and escalation bundles.
docs/APPLE_RELEASE.md:89:SecureWave does not use Hotspot Helper. A Hotspot Helper entitlement is not the
docs/guides/DESKTOP_THREE_PROTOCOL_PLAN.md:7:desktop first with WireGuard primary; OpenVPN is limited to the already
docs/guides/DESKTOP_THREE_PROTOCOL_PLAN.md:8:certified Linux runtime/helper dataplane path unless separately promoted after
docs/guides/DESKTOP_THREE_PROTOCOL_PLAN.md:17:- Post-v1 target: evaluate `WireGuard`, `OpenVPN`, and `IKEv2` across desktop:
docs/guides/DESKTOP_THREE_PROTOCOL_PLAN.md:20:- Treat `OpenVPN` as the compatibility and restrictive-network fallback.
docs/guides/DESKTOP_THREE_PROTOCOL_PLAN.md:28:  - `OpenVPN` for blocked/restrictive networks, TCP fallback, and legacy compatibility
docs/guides/DESKTOP_THREE_PROTOCOL_PLAN.md:35:  - Product target: `WireGuard + OpenVPN + IKEv2`
docs/guides/DESKTOP_THREE_PROTOCOL_PLAN.md:36:  - Initial confidence order: `WireGuard`, then `OpenVPN`, then `IKEv2`
docs/guides/DESKTOP_THREE_PROTOCOL_PLAN.md:38:  - Product target: `WireGuard + OpenVPN + IKEv2`
docs/guides/DESKTOP_THREE_PROTOCOL_PLAN.md:39:  - Initial confidence order: `WireGuard`, then `OpenVPN`, then `IKEv2`
docs/guides/DESKTOP_THREE_PROTOCOL_PLAN.md:41:  - Product target: `WireGuard + OpenVPN + IKEv2`
docs/guides/DESKTOP_THREE_PROTOCOL_PLAN.md:42:  - Initial confidence order: `WireGuard`, then `IKEv2`, then `OpenVPN`
docs/guides/DESKTOP_THREE_PROTOCOL_PLAN.md:52:  - Use `OpenVPN` as the first general fallback if `WireGuard` is unavailable.
docs/guides/DESKTOP_THREE_PROTOCOL_PLAN.md:55:  - Keep strict server-material validation for `OpenVPN` and `IKEv2`.
docs/guides/DESKTOP_THREE_PROTOCOL_PLAN.md:70:  - `WireGuard`, `OpenVPN`, and `IKEv2` profile issuance stay typed and validated.
docs/guides/DESKTOP_THREE_PROTOCOL_PLAN.md:71:  - Misconfigured `OpenVPN` and `IKEv2` remain blocked with specific error codes.
docs/guides/DESKTOP_THREE_PROTOCOL_PLAN.md:74:  - Prioritize Linux `WireGuard/OpenVPN/IKEv2` runtime readiness first, then Windows and macOS parity.
docs/guides/DESKTOP_THREE_PROTOCOL_PLAN.md:82:- `OpenVPN` and `IKEv2` are strategic fallbacks, not equal defaults.
docs/HETZNER_RUNBOOK.md:60:- Creates `securewave` admin user (sudo + docker)
docs/HETZNER_RUNBOOK.md:85:ssh securewave@<server-ip> 'sudo cat /etc/wireguard/keys/server_public.key'
docs/RELEASE_CHECKLIST.md:152:- [ ] Do not request Hotspot Helper; SecureWave is not a captive Wi-Fi helper app
docs/RELEASE_CHECKLIST.md:240:sudo apt-get install -y appimage-builder
securewave_app/DEBUG_CHECKLIST.md:30:- WireGuard is only connected after `wg-quick up` returns successfully and
securewave_app/DEBUG_CHECKLIST.md:33:- OpenVPN requires a non-empty `openvpn_config` from the backend and a live
securewave_app/DEBUG_CHECKLIST.md:34:  `securewave-openvpn` process after startup.
securewave_app/DEBUG_CHECKLIST.md:41:which wg-quick openvpn swanctl ipsec pkexec
securewave_app/DEBUG_CHECKLIST.md:44:pgrep -af 'securewave-openvpn|securewave.ovpn'
securewave_app/LINUX_VPN_SETUP.md:1:# Linux VPN Setup (wg-quick)
securewave_app/LINUX_VPN_SETUP.md:3:SecureWave uses `wg-quick` to bring up a WireGuard tunnel on Linux. The Flutter
securewave_app/LINUX_VPN_SETUP.md:4:MethodChannel writes the config to disk and executes `wg-quick up/down`.
securewave_app/LINUX_VPN_SETUP.md:9:- Backend: `wg-quick`
securewave_app/LINUX_VPN_SETUP.md:14:- WireGuard tools installed (`wg-quick` on PATH)
securewave_app/LINUX_VPN_SETUP.md:15:- Permission to run `wg-quick` (typically via sudo)
securewave_app/LINUX_VPN_SETUP.md:21:   - Ubuntu/Debian: `sudo apt-get install wireguard`
securewave_app/LINUX_VPN_SETUP.md:25:   - `sudo wg show securewave`
securewave_app/LINUX_VPN_SETUP.md:28:If `wg-quick` is not found, Flutter receives `vpn_unavailable`. In demo mode
securewave_app/README.md:15:- WireGuard/OpenVPN profile fetch from API and handoff to native bridge
securewave_app/IOS_VPN_SETUP.md:53:SecureWave does not use Hotspot Helper. The iOS VPN request should be scoped to
securewave_app/LINUX_RUNTIME_QA.md:5:native helper has created the expected tunnel state.
securewave_app/LINUX_RUNTIME_QA.md:10:- `wg-quick` installed for WireGuard.
securewave_app/LINUX_RUNTIME_QA.md:11:- `openvpn` installed for OpenVPN.
securewave_app/LINUX_RUNTIME_QA.md:12:- `pkexec` available, or run the app with the required privileges.
securewave_app/LINUX_RUNTIME_QA.md:63:-> helper command/config -> native result -> Dart state update.
securewave_app/LINUX_RUNTIME_QA.md:69:3. Confirm `wg-quick up` succeeds and interface `securewave` exists.
securewave_app/LINUX_RUNTIME_QA.md:82:### OpenVPN
securewave_app/LINUX_RUNTIME_QA.md:84:1. Select OpenVPN only when the backend returns `openvpn_config`.
securewave_app/LINUX_RUNTIME_QA.md:86:3. Confirm the OpenVPN process remains alive after startup.
securewave_app/LINUX_RUNTIME_QA.md:89:6. Confirm the OpenVPN pid file is removed and no SecureWave OpenVPN process is
securewave_app/LINUX_RUNTIME_QA.md:95:pgrep -af 'securewave-openvpn|securewave.ovpn'
securewave_app/LINUX_RUNTIME_QA.md:104:until a future patch wires profile import, strongSwan connection start, status
securewave_app/LINUX_RUNTIME_QA.md:124:- Helper command availability: `which wg-quick openvpn swanctl ipsec pkexec`.
securewave_app/LINUX_RUNTIME_QA.md:125:- Tunnel state: `ip link`, `ip route`, `wg show`, `pgrep -af openvpn`.
securewave_app/ios/ThirdParty/wireguard-apple/MOBILECONFIG.md:78:    - `WgQuickConfig` (string): Should be a WireGuard configuration in [wg-quick(8)] / [wg(8)] format.
securewave_app/ios/ThirdParty/wireguard-apple/MOBILECONFIG.md:139:[wg-quick(8)]: https://git.zx2c4.com/wireguard-tools/about/src/man/wg-quick.8
