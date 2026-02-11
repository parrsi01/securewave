# WireGuard Deployment

SecureWave uses a single WireGuard server on the Hetzner host.

## Steps

1. Provision the server via Terraform (`infrastructure/hetzner`).
2. Bootstrap the host (`scripts/hetzner_bootstrap.sh`).
3. Install WireGuard on the server:

```bash
apt-get update
apt-get install -y wireguard
```

4. Configure `wg0.conf` and enable:

```bash
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0
```

## Backend Integration

Set these environment variables:

- `WG_ENDPOINT=<public-ip>:51820`
- `WG_SSH_HOST=<public-ip>`
- `WG_SSH_USER=securewave`
- `WG_SSH_KEY_PATH=/path/to/private_key`

## Firewall

The default firewall opens UDP 51820 and SSH only.
