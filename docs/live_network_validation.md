# Live Network Validation

This guide runs real SecureWave VPN network validation against a deployed backend and WireGuard node.

## Prerequisites

- Reachable backend URL (`LIVE_API_BASE_URL`), for example `https://138.199.204.139.nip.io`
- Linux host with `wireguard-tools`, `curl`, `iproute2`
- Root privileges for real tunnel setup (`sudo`)
- Optional Android/Windows command templates for cross-platform orchestration

## Required Environment Variables

```bash
export LIVE_API_BASE_URL="https://<PUBLIC-IP>.nip.io"
export LIVE_VALIDATION_PASSWORD="<strong-non-default-password>"
```

Optional:

```bash
export LIVE_VALIDATION_USERS=3
export LIVE_VALIDATION_SERVER_ID="hel1-01"
export LIVE_ALLOWED_DNS="94.140.14.14,94.140.15.15,1.1.1.1"
export LIVE_HTTP_PROBE_URL="https://api.ipify.org"
export LIVE_PUBLIC_IP_ENDPOINT="https://api.ipify.org"
```

## Run End-to-End Validation

```bash
sudo -E bash dev_tools/sandbox/live_validation/run_live_validation.sh --strict --linux --users 3
```

Artifacts are written to `artifacts/live_validation/`:

- `live_e2e_result.json`
- `handshake_stats.csv`
- `dns_checks.csv`
- `geo_latency_report.csv`
- `validation_summary.json`
- `PRODUCTION_NETWORK_READINESS.md`

## Run Concurrency Stress Validation

```bash
sudo -E bash dev_tools/sandbox/live_validation/run_live_stress_tests.sh --strict --linux --workers 4 --cycles 5
```

Stress outputs include:

- `latency_metrics.csv`
- `jitter_metrics.csv`
- `throughput_metrics.csv`
- `fail_rate_metrics.csv`
- `live_stress_summary.json`

## Fault Injection

Safe mode (non-destructive):

```bash
python dev_tools/sandbox/live_validation/network_failure_cases.py \
  --api-base-url "$LIVE_API_BASE_URL" \
  --output-dir artifacts/live_validation
```

Destructive mode (root, explicit):

```bash
sudo -E python dev_tools/sandbox/live_validation/network_failure_cases.py \
  --api-base-url "$LIVE_API_BASE_URL" \
  --output-dir artifacts/live_validation \
  --execute --strict
```

## Android / Windows Command Templates

Set these before running live scripts when orchestrating those platforms:

```bash
export LIVE_ANDROID_CONNECT_CMD='adb shell <connect-command> {config_path} {interface}'
export LIVE_ANDROID_DISCONNECT_CMD='adb shell <disconnect-command> {interface}'
export LIVE_ANDROID_HANDSHAKE_CMD='adb shell wg show {interface} latest-handshakes'

export LIVE_WG_WINDOWS_CONNECT_CMD='wireguard.exe /installtunnelservice "{config_path}"'
export LIVE_WG_WINDOWS_DISCONNECT_CMD='wireguard.exe /uninstalltunnelservice "{interface}"'
export LIVE_WG_WINDOWS_HANDSHAKE_CMD='wg.exe show "{interface}" latest-handshakes'
```

## CI Optional Job

`test.yml` includes an optional `live-network` job.

Enable it by setting repository variable:

- `LIVE_NETWORK_ENABLED=true`

And secrets:

- `LIVE_API_BASE_URL`
- `LIVE_VALIDATION_PASSWORD`

The job runs strict live validation and uploads `artifacts/live_validation`.
