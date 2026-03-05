# SecureWave VPS Operations

## Execution Model
All infrastructure operations run directly on the Hetzner VPN server.

Operator workflow:

1. `ssh root@vpn-server`
2. `cd /path/to/securewave`
3. Run the required operational script locally

There is no dependency on a developer workstation for provisioning, health checks, diagnostics, or validation.

## Log Location
All operational scripts write to:

- `/var/log/securewave/`

Key files:

- `/var/log/securewave/install_vpn_stack.log`
- `/var/log/securewave/vpn_health_check.log`
- `/var/log/securewave/health_report.log`
- `/var/log/securewave/restart_vpn_services.log`
- `/var/log/securewave/rotate_logs.log`
- `/var/log/securewave/backup_vpn_configs.log`
- `/var/log/securewave/cleanup_stale_interfaces.log`
- `/var/log/securewave/vpn_diagnostics.log`
- `/var/log/securewave/run_securewave_ops.log`
- `/var/log/securewave/securewave_validate_wireguard.log`
- `/var/log/securewave/securewave_validate_openvpn.log`
- `/var/log/securewave/securewave_validate_ikev2.log`

## Provisioning
Initial package install and base host preparation:

```bash
tools/provisioning/install_vpn_stack.sh
```

What it does:

- Installs VPN and support packages
- Enables IPv4 and IPv6 forwarding
- Adds additive NAT and forwarding rules
- Creates `/etc/securewave/*` configuration directories
- Enables long-lived services where applicable

## Health Monitoring
Run a one-shot operational health check:

```bash
tools/monitoring/vpn_health_check.sh
```

This writes a human-readable health report to:

- `/var/log/securewave/health_report.log`

## Maintenance
Restart VPN-related services safely:

```bash
tools/maintenance/restart_vpn_services.sh
```

Rotate SecureWave logs:

```bash
tools/maintenance/rotate_logs.sh
```

Back up VPN configuration:

```bash
tools/maintenance/backup_vpn_configs.sh
```

Clean validation-only leftovers:

```bash
tools/maintenance/cleanup_stale_interfaces.sh
```

## Diagnostics
Collect a point-in-time diagnostic bundle:

```bash
tools/diagnostics/vpn_diagnostics.sh
```

This writes the detailed report to:

- `/tmp/securewave_diagnostics_<timestamp>.log`

## Validation
To run the full data-plane validation locally on the VPS:

```bash
export API_BASE_URL="https://vpn.example.com/api"
export AUTH_TOKEN="your-bearer-token"
export PROFILE_OUTPUT_DIR="/tmp/securewave_vps_validation"
./run_all_validation_tools.sh
```

Optional:

- `WIREGUARD_SERVER_ID`
- `OPENVPN_SERVER_ID`
- `IKEV2_SERVER_ID`

## Master Operational Runner
Run health checks only:

```bash
./run_securewave_ops.sh
```

Run health checks and the full validation suite:

```bash
export API_BASE_URL="https://vpn.example.com/api"
export AUTH_TOKEN="your-bearer-token"
export PROFILE_OUTPUT_DIR="/tmp/securewave_vps_validation"
./run_securewave_ops.sh --with-validation
```

## Safety Notes
- All scripts require `root`.
- All scripts refuse to run if the host does not look like the Hetzner VPN server.
- Validation scripts use local namespaces or safe-mode client configuration to avoid changing primary server connectivity.
- Maintenance cleanup targets only validation artifacts with the `swv-` naming convention.
