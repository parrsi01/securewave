# VPN Regression Test Harness

## Purpose

`./scripts/regression_vpn_stack.sh` runs an end-to-end regression pass for WireGuard, OpenVPN, and IKEv2 coexistence and teardown isolation.

It validates:
- policy routing integrity
- NAT chain isolation
- teardown safety
- throughput/shaping guardrails
- randomized connect/disconnect transitions
- drift in global routing/NAT/shaping state

## How To Run

Run from repository root as root:

```bash
cd /home/sp/cyber-course/projects/securewave
sudo ./scripts/regression_vpn_stack.sh
```

Output artifacts:
- Main report: `reports/regression_<timestamp>.txt`
- Per-step snapshots: `reports/snapshots/*.txt`

## Recurring Loop Mode

To run until pass and overwrite a single latest output file each attempt:

```bash
cd /home/sp/cyber-course/projects/securewave
sudo ./scripts/regression_vpn_loop.sh
```

Latest file (overwritten on every attempt):
- `reports/regression_latest.txt`

Optional environment variables:
- `SW_REGRESSION_INTERVAL_SECONDS` (default: `15`)
- `SW_REGRESSION_MAX_ATTEMPTS` (default: `0`, meaning infinite loop until pass)

## What The Harness Executes

### Preflight checks
The harness runs these scripts in order:
- `scripts/verify_policy_routing.sh`
- `scripts/verify_nat_isolation.sh`
- `scripts/verify_teardown_safety.sh`
- `scripts/verify_wireguard_regression.sh`
- `scripts/verify_openvpn_connectivity.sh`
- `scripts/verify_ikev2_coexistence.sh`
- `scripts/verify_throughput_sanity.sh`
- `scripts/verify_shaping.sh`

If a preflight script is missing or fails, the harness records a failure and exits non-zero.

### Randomized lifecycle phase
- Picks random connect order for `wireguard`, `openvpn`, `ikev2`.
- Picks random disconnect order.
- Uses real lifecycle commands when present:
  - `/usr/local/bin/securewave-vpn-routing`
  - fallback: `scripts/setup_vpn_routing.sh`
- If no lifecycle command exists, enters dry-run mode and still performs drift checks/snapshots.

### Snapshots captured after baseline and every step
- `ip rule`
- `ip route show table 100`
- `ip route show table 200`
- `ip route show table 300`
- `iptables -t nat -S`
- `tc qdisc show`
- interface counters (`wg0`, `tun0`, `ipsec0`) if interfaces exist

## Expected Output

Successful run includes:
- `regression result: OK`
- `report file: reports/regression_<timestamp>.txt`
- `dry-run steps: 0` when lifecycle commands are available

Failure run includes:
- `regression result: FAILED (<n> issues)`
- one or more `FAIL:` lines with signature-specific details

## Common Failure Signatures

- `missing preflight script: scripts/verify_wireguard_regression.sh`
  - Required verification script is absent from repo.
- `preflight failed: scripts/verify_nat_isolation.sh`
  - NAT chain layout does not meet expected isolated-chain model.
- `FAIL: main default route drift detected`
  - Global default route was modified unexpectedly.
- `FAIL: missing NAT chain WG_NAT` (or OVPN/IKEV2)
  - Chain removed/flushed or never created.
- `FAIL: POSTROUTING hook count ... expected 1`
  - Hook duplication or teardown side-effect.
- `FAIL: teardown of <proto> removed or duplicated <other> hook`
  - Teardown is not isolated and affected another protocol.
- `FAIL: global shaping detected on default interface <iface>`
  - QoS policy leaked from VPN interface to global/default interface.

## Rollback Guidance

If regression fails after recent routing/NAT changes:

1. Re-apply known-good routing/NAT ownership:
```bash
sudo ./scripts/setup_vpn_routing.sh setup
```

2. Re-run focused verifiers:
```bash
sudo ./scripts/verify_policy_routing.sh
sudo ./scripts/verify_nat_isolation.sh
sudo ./scripts/verify_teardown_safety.sh
```

3. Re-run full regression:
```bash
sudo ./scripts/regression_vpn_stack.sh
```

If failures persist, inspect:
- latest `reports/regression_<timestamp>.txt`
- matching files under `reports/snapshots/`

Use those snapshots to identify the first step where drift appears.
