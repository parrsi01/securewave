# SecureWave Full-Stack Alignment Report

- Run ID: `20260227_011144`
- Base URL: `http://127.0.0.1:8000`
- Output dir: `/home/sp/cyber-course/projects/securewave/tools/runtime_probe/out/fullstack_20260227_011144`

## Baseline Network Capture
## Verdict

- Passes: 0
- Fails: 1
- Warnings: 0
- Exceptions: 4

## Passes

- None

## Fails

- Backend health endpoint unreachable.

## Warnings

- None

## Exceptions

- premium: skipped because login failed or credentials missing.
- free: skipped because login failed or credentials missing.
- Flutter validation slice blocked by sandbox/write permissions on Flutter cache.
- Runtime probe blocked by host privilege/elevation configuration.

## Evidence Files

- Baseline network: `baseline_ip_addr.txt`, `baseline_ip_route.txt`, `baseline_ip_rule.txt`, `baseline_nmcli_devices.txt`
- Backend checks: `backend_health.txt`, `premium_protocols.txt`, `premium_regions.txt`, `free_protocols.txt`
- Flutter tests: `flutter_validation_tests.txt`
- Runtime probe: `runtime_probe_run.txt`
- Post network: `post_nmcli_devices.txt`, `post_ip_route.txt`, `post_ip_rule.txt`
