# OpenVPN Linux Certification Report - 2026-06-28

## 1. Executive summary

OpenVPN is improved but not fully release-ready on this workstation because the fixed helper package is not installed. The root cause of the previous app-path failure was not the generated OpenVPN profile or server reachability: OpenVPN successfully created `tun0` and routed traffic when launched with the same generated profile. The app failed because the privileged helper let OpenVPN create the readiness log as `root:root` mode `0600`, so the unprivileged Flutter runner could not read `Initialization Sequence Completed`.

The source/package fix now pre-creates the OpenVPN PID and log files as the owner of the generated `.ovpn` profile, bumps the helper contract to `7`, and makes OpenVPN starts reject stale installed helpers. The current host still has installed helper contract `6`, and non-interactive package installation timed out under PolicyKit, so the final app-path proof is intentionally blocked until the new package/helper is installed.

## 2. What is proven

- The generated OpenVPN profile used by the app path is structurally complete and includes CA, client certificate, client key, and `tls-crypt` material. Secret material was inspected only structurally and was not printed.
- The same generated profile launches through the installed SecureWave helper and establishes a real tunnel: `tun0` appeared and `ip route get 1.1.1.1` routed via `tun0` in about 2 seconds.
- OpenVPN stop cleanup removed `tun0` after the direct helper run.
- The packaged `.deb` contains the updated helper and contract file from the source tree.
- Unit tests, Flutter tests, Flutter analyzer, and Linux package build passed.

## 3. What failed

- `python3 scripts/linux_vpn_runtime_verifier.py --json --pkexec-timeout 20` failed because `/usr/local/libexec/securewave-wg-quick.contract` is still `6`, while source now requires `7`.
- `python3 scripts/linux_app_vpn_tunnel_proof.py --protocol openvpn --hold-seconds 20 --evidence-timeout 180 --pkexec-timeout 20 --json` did not run the tunnel proof because its baseline verifier correctly rejected the stale installed helper.
- `bash scripts/demo_preflight.sh --skip-build` failed on the same installed helper contract drift.
- `pkexec --disable-internal-agent /usr/bin/dpkg -i securewave_app/build/packaging/securewave-vpn_4.0.0+1_arm64.deb` timed out, so this session could not install the fixed helper non-interactively.

## 4. Root cause

The OpenVPN daemon was able to connect, but the app readiness check required both:

- `Initialization Sequence Completed` in the OpenVPN log.
- Tunnel route/interface evidence.

The helper launched OpenVPN as root with `--log "$log_file"`. OpenVPN created the log as `root:root` mode `0600`, so the app process could not read it. The runner therefore never observed `Initialization Sequence Completed`, reported a failed start, and cleaned up a tunnel that otherwise had real route evidence.

## 5. Files changed

- `securewave_app/packaging/linux/securewave-wg-quick`
- `securewave_app/packaging/linux/securewave-wg-quick.contract`
- `securewave_app/linux/runner/my_application.cc`
- `scripts/linux_vpn_runtime_verifier.py`
- `scripts/demo_preflight.sh`
- `tests/unit/test_linux_vpn_runner_contract.py`
- `tests/unit/test_linux_vpn_runtime_verifier.py`
- `docs/DEVOPS_REPORT_OPENVPN_LINUX_CERTIFICATION_2026-06-28.md`

## 6. Validation performed

- `bash -n securewave_app/packaging/linux/securewave-wg-quick scripts/demo_preflight.sh scripts/linux_vpn_runtime_verifier.py scripts/linux_app_vpn_tunnel_proof.py` passed.
- `pytest -q tests/unit/test_linux_vpn_runner_contract.py tests/unit/test_linux_vpn_runtime_verifier.py tests/unit/test_linux_app_vpn_tunnel_proof.py` passed: 32 tests.
- `flutter analyze` passed.
- `flutter test` passed: 37 tests.
- `bash securewave_app/scripts/build_deb.sh` passed and built `securewave_app/build/packaging/securewave-vpn_4.0.0+1_arm64.deb`.
- `dpkg-deb -c securewave_app/build/packaging/securewave-vpn_4.0.0+1_arm64.deb` confirmed the package contains the SecureWave helper, contract, and polkit rule.
- `python3 scripts/linux_vpn_runtime_verifier.py --json --pkexec-timeout 20` failed only on installed helper contract drift: installed `6`, required `7`.
- `bash scripts/demo_preflight.sh --skip-build` failed only on installed helper contract drift: installed `6`, required `7`.

## 7. Why OpenVPN is or is not release-ready

OpenVPN is not release-ready on this workstation yet because the fixed helper is not installed and the required app-path tunnel proof cannot honestly pass against stale helper contract `6`.

The source and package are ready for the next install/proof attempt: stale helpers are rejected, and the packaged helper now creates app-readable OpenVPN readiness files without weakening the real tunnel proof.

## 8. Release risk

Remaining release risk is operational packaging drift, not OpenVPN profile generation or server connectivity. A machine with the stale contract `6` helper will fail the verifier and preflight until the fixed package installs contract `7`.

## 9. Exact next engineering step

Install the built package or otherwise deploy the contract `7` helper to `/usr/local/libexec/securewave-wg-quick` and `/usr/local/libexec/securewave-wg-quick.contract`, then rerun:

```bash
python3 scripts/linux_vpn_runtime_verifier.py --json --pkexec-timeout 20
python3 scripts/linux_app_vpn_tunnel_proof.py --protocol openvpn --hold-seconds 20 --evidence-timeout 180 --pkexec-timeout 20 --json
bash scripts/demo_preflight.sh --skip-build
```
