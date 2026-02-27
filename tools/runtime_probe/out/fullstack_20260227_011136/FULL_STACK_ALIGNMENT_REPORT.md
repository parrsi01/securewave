# SecureWave Full-Stack Alignment Report

- Run ID: `20260227_011136`
- Base URL: `http://127.0.0.1:8000`
- Output dir: `/home/sp/cyber-course/projects/securewave/tools/runtime_probe/out/fullstack_20260227_011136`

## Baseline Network Capture
## Verdict

- Passes: 0
- Fails: 1
- Warnings: 1
- Exceptions: 3

## Passes

- None

## Fails

- Backend health endpoint unreachable.

## Warnings

- Runtime probe skipped by flag.

## Exceptions

- premium: skipped because login failed or credentials missing.
- free: skipped because login failed or credentials missing.
- Flutter validation slice blocked by sandbox/write permissions on Flutter cache.

## Evidence Files

- Baseline network: `baseline_ip_addr.txt`, `baseline_ip_route.txt`, `baseline_ip_rule.txt`, `baseline_nmcli_devices.txt`
- Backend checks: `backend_health.txt`, `premium_protocols.txt`, `premium_regions.txt`, `free_protocols.txt`
- Flutter tests: `flutter_validation_tests.txt`
- Runtime probe: `runtime_probe_run.txt`
- Post network: `post_nmcli_devices.txt`, `post_ip_route.txt`, `post_ip_rule.txt`
