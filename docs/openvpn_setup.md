# OpenVPN Setup (Hetzner Ubuntu)

This document provisions a real OpenVPN service for SecureWave on a Hetzner host.

## Scope
- Real OpenVPN server (`openvpn-server@securewave`)
- mTLS client issuance with short-lived backend provisioning tokens
- Root-only secret storage under `/etc/securewave/secrets`
- UFW rules and NAT setup
- Rotation and break-glass paths

## Cost-Safe Topology
- Default to one Hetzner node (`cx23`/`cx33`)
- Keep control-plane + data-plane on a single host unless throughput requires split

## Ports
Minimum inbound ports (Hetzner firewall + UFW):
- `22/tcp` (admin)
- `80/tcp`, `443/tcp` (website/API)
- `51820/udp` (WireGuard)
- `1194/udp` (OpenVPN)

Optional:
- `443/tcp` for OpenVPN TCP **only when HTTPS is not bound on 443 on this host**.

## Provision
Run on the VPN host as root:

```bash
bash scripts/provision_openvpn.sh
```

Optional env vars:
- `OPENVPN_UDP_PORT` (default `1194`)
- `OPENVPN_ENABLE_TCP_443` (`0`/`1`, default `0`)
- `OPENVPN_SERVER_CN`
- `OPENVPN_NETWORK_CIDR` (default `10.44.0.0/24`)
- `OPENVPN_INTERFACE` (egress NIC)
- `OPENVPN_DNS_1`, `OPENVPN_DNS_2`

## Installed Components
- `/etc/openvpn/server/securewave.conf`
- `/etc/securewave/secrets/openvpn/easy-rsa/` (CA/server/client PKI)
- `/etc/securewave/secrets/openvpn/tls-crypt.key`
- `/usr/local/bin/securewave-openvpn-issue-client`
- `/usr/local/bin/securewave-openvpn-revoke-client`
- `/usr/local/bin/securewave-validate-provisioning-token`

## Backend Integration
Required backend env vars:

```bash
SECUREWAVE_OPENVPN_AUTH_MODE=mtls
SECUREWAVE_PROVISIONING_TOKEN_SECRET=<same secret as /etc/securewave/secrets/provisioning_token_secret>
SECUREWAVE_OPENVPN_CERT_VALID_DAYS=30
SECUREWAVE_PROVISIONING_TOKEN_TTL_SECONDS=300
```

Server helpers must be reachable via backend SSH path (`WG_SSH_USER`, `WG_SSH_KEY_PATH`).

## Validation
On VPN host:

```bash
systemctl status openvpn-server@securewave --no-pager
ss -lun | rg 1194
ufw status
```

From backend/API side:
- Call `POST /api/vpn/profile` with `protocol=openvpn`
- Ensure response contains `profile.type=openvpn` and `auth_method=mtls`

## Rotation
Run on VPN host:

```bash
SECUREWAVE_ROTATE_CONFIRM=YES bash scripts/rotate_openvpn_ca.sh
```

Effect:
- Rebuilds OpenVPN CA and server cert
- Existing issued client certs become invalid

## Break Glass
1. Stop OpenVPN service:
```bash
systemctl stop openvpn-server@securewave
```
2. Restore latest backup from `/var/backups/securewave/openvpn-pki-*.tar.gz`
3. Start service:
```bash
systemctl start openvpn-server@securewave
```
4. Revoke suspicious clients with:
```bash
securewave-openvpn-revoke-client --common-name <CN>
```

## Security Notes
- Do not commit any PKI files.
- Keep `/etc/securewave/secrets` owner `root:root`, mode `700`.
- Rotate provisioning token secret if backend host trust boundary changes.
