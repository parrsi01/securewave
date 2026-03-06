# Outage Classification

## Inputs
- `ping -c 3 138.199.204.139`: 100% packet loss
- `traceroute -n 138.199.204.139`: path reaches Hetzner-side hops, then times out near destination
- `nc -vz -w 3 138.199.204.139 22`: timeout
- `ssh root@138.199.204.139` with strict timeout: timeout
- Hetzner API check via `hcloud`: no active context/token available locally

## Verdict
- **probable_self_lockout**

## Rationale
- Outage occurred immediately after route/egress experiments on the host.
- TCP/22 timeout plus complete ICMP loss can be explained by broken host routing/firewall state.
- Provider-wide outage cannot be ruled out without Hetzner panel/API power-status verification.

## Immediate next action
- Use Hetzner console/rescue path to restore default route and SSH ingress (see `REPORTS/console_recovery_steps.md`).
