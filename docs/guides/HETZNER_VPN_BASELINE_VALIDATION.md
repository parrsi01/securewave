# Hetzner VPN Baseline Validation

Use this after provisioning/deploy to fail fast when a VPN node is misconfigured.

## What it validates

- Host/network baseline:
  - `net.ipv4.ip_forward=1`
  - primary egress `MASQUERADE` NAT rule exists
  - firewall attached
  - private network attached (required by default)
- WireGuard baseline:
  - runtime present (`wg`, `wg-quick`)
  - `wg-quick@wg0` active
  - port bound
  - config exists (`/etc/wireguard/wg0.conf`)
- OpenVPN baseline (default required):
  - runtime + config + cert material present
  - service active
  - port bound (UDP or TCP)
- IKEv2 baseline (default required):
  - runtime + config + cert material present
  - service active
  - UDP 500 and 4500 bound
- Optional backend registry consistency:
  - live servers must exist in backend `vpn_servers`
  - IP mismatches fail validation

## Command

```bash
cd /home/sp/cyber-course/projects/securewave
HETZNER_API_TOKEN=... \
WG_SSH_KEY_PATH=~/.ssh/securewave_prod \
bash scripts/ops/validate_vpn_node_baseline.sh
```

## Common variants

Require only WireGuard:

```bash
bash scripts/ops/validate_vpn_node_baseline.sh \
  --require-private-network false \
  --require-openvpn false \
  --require-ikev2 false
```

Scope by server prefix:

```bash
bash scripts/ops/validate_vpn_node_baseline.sh \
  --name-prefix securewave
```

## Release integration

`scripts/release_hetzner.sh` supports optional baseline enforcement after `apply`.

```bash
VALIDATE_VPN_BASELINE=true \
HETZNER_API_TOKEN=... \
WG_SSH_KEY_PATH=~/.ssh/securewave_prod \
bash scripts/release_hetzner.sh apply
```

If validation fails, the release command exits non-zero.
