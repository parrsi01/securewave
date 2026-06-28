# Linux Live Certification DevOps Report - 2026-06-28

## 1. Executive summary
SecureWave Linux is live-certified for the primary WireGuard path and the IKEv2
path on this host. Both paths used the app-driven REST/profile flow and the
installed SecureWave helper through PolicyKit without manual admin password
entry during normal connect/disconnect operation.

OpenVPN is not release-ready. The app fetched a live profile and invoked the
scoped helper without an admin prompt, but the OpenVPN process did not reach
`Initialization Sequence Completed` plus tunnel route evidence. A minimal Linux
runner cleanup fix was added so failed OpenVPN starts stop the daemon and remove
residue before reporting the failure.

## 2. What is proven live
- WireGuard app-driven proof connected to `de-nue-1`, raised `sw-wg`, routed
  `1.1.1.1` through `sw-wg`, passed `scripts/demo_preflight.sh --live-go-no-go`
  while connected, then cleaned up with no residue.
- IKEv2 app-driven proof connected to `de-nue-1`, showed active
  `SecureWave-IKEv2` NetworkManager VPN state, DNS/route data, and XFRM ESP
  state, then disconnected and cleaned up.
- The installed helper contract is `6`, matching the runner expectation.
- The installed production polkit rule is aligned to the packaged rule. After
  revoking temporary PolicyKit authorization, the SecureWave helper remained
  prompt-free while generic `pkexec /usr/bin/id` timed out.
- Live API health, email health, download manifest, live Linux inventory, and
  disposable account/device checks passed through the preflight path.

## 3. What still requires interactive auth
No intended SecureWave helper operation tested in this pass required interactive
admin authentication after the production polkit rule was installed and stale
host-local rules were removed.

Generic `pkexec` operations are not prompt-free after temp authorization is
revoked. That is expected and confirms the result is scoped to the SecureWave
helper path, not a blanket local privilege bypass.

## 4. Root cause
The original host state was stale: `/etc/polkit-1/rules.d/50-securewave-wg.rules`
did not match the current packaged rule and `/etc/polkit-1/rules.d/80-securewave-
wireguard.rules` was a host-local leftover. Installing the current production
rule and removing the stale host-local rule restored the intended helper-scoped
promptless behavior.

OpenVPN has a separate runtime readiness gap. The live app path can start the
OpenVPN daemon, but the daemon does not reach both initialization and tunnel
route evidence within the runner's evidence window. Before this pass, that
failed-start path could leave `tun0`, split routes, and an OpenVPN daemon
behind. The cleanup gap was fixed in the Linux runner; the OpenVPN connectivity
failure itself remains.

## 5. Files changed
- `securewave_app/linux/runner/my_application.cc`
- `tests/unit/test_linux_vpn_runner_contract.py`
- `docs/DEVOPS_REPORT_LINUX_LIVE_CERTIFICATION_2026-06-28.md`

Host state changed during certification:
- Installed the current packaged `50-securewave-wg.rules` to
  `/etc/polkit-1/rules.d/50-securewave-wg.rules`.
- Removed stale host-local `/etc/polkit-1/rules.d/80-securewave-wireguard.rules`.
- Reloaded/restarted `polkit.service`.

## 6. Validation performed
- `.venv/bin/python -m pytest tests/unit -q` passed before the OpenVPN cleanup
  patch.
- `cd securewave_app && flutter analyze && flutter test` passed before the
  OpenVPN cleanup patch.
- `python3 scripts/linux_vpn_runtime_verifier.py --json --pkexec-timeout 20`
  passed before and after live protocol attempts.
- `bash scripts/demo_preflight.sh --skip-build` passed.
- `SKIP_FLUTTER=true bash scripts/devops_preflight.sh` passed.
- `bash scripts/demo_preflight.sh --live-go-no-go` passed while a real
  app-driven `sw-wg` session was connected.
- `bash securewave_app/scripts/build_deb.sh` passed and generated a package whose
  postinst installs the helper/rule and reloads PolicyKit.
- WireGuard live proof passed through `scripts/linux_app_vpn_tunnel_proof.py`.
- IKEv2 live proof passed through `scripts/linux_app_vpn_tunnel_proof.py`.
- OpenVPN live proof failed to connect but, after the cleanup fix, final cleanup
  verification passed with no `tun0`, split route, or daemon residue.
- Focused post-fix checks passed:
  `.venv/bin/python -m pytest tests/unit/test_linux_vpn_runner_contract.py
  tests/unit/test_linux_vpn_runtime_verifier.py
  tests/unit/test_linux_app_vpn_tunnel_proof.py -q`
  and `cd securewave_app && flutter analyze`.

## 7. Why 24/7 always-available API-controlled protocol operation is or is not true
It is true for WireGuard on this host for the tested live path: the app acquired
a live profile, started the real tunnel with no admin prompt, kept live API/DNS
reachable through the tunnel, and disconnected cleanly.

It is true for IKEv2 on this host for the tested live path: the app acquired a
live profile, established NetworkManager plus XFRM ESP runtime evidence with no
admin prompt, and disconnected cleanly.

It is not true for OpenVPN. The app/API/helper path starts the daemon but does
not achieve certified tunnel evidence. OpenVPN must stay out of a 24/7
release-grade claim until that runtime failure is fixed and rerun live.

## 8. Release risk
- WireGuard: low runtime privilege risk on this host after installed-rule
  alignment; still requires the package install/postinst to be used on clean
  machines.
- IKEv2: low runtime privilege risk on this host after installed-rule alignment;
  still needs broader network diversity testing for NAT/firewall cases.
- OpenVPN: high release risk if advertised as production-ready. It fails live
  connection certification and previously left residue on failed start. Residue
  cleanup is now fixed, but the protocol is still not connect-ready.

## 9. Exact next engineering step
Debug OpenVPN server/profile compatibility from the daemon log and generated
profile, then rerun:

```bash
python3 scripts/linux_app_vpn_tunnel_proof.py --protocol openvpn --hold-seconds 20 --evidence-timeout 180 --pkexec-timeout 20 --json
python3 scripts/linux_vpn_runtime_verifier.py --json --pkexec-timeout 20
```

The OpenVPN protocol should only be marked release-ready when the proof reports
connected state, tunnel route evidence, successful disconnect, and a clean final
verifier.
