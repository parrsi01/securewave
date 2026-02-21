# IKEv2/IPsec Setup (Hetzner Ubuntu)

This document provisions real strongSwan IKEv2 service for SecureWave with EAP-TLS client certs.

## Scope
- Real strongSwan IKEv2 (`strongswan-starter` or `strongswan`)
- Per-device certificate issuance with backend short-lived provisioning tokens
- Root-only secret storage under `/etc/securewave/secrets`
- UFW + NAT rules
- Rotation and break-glass procedures

## Ports
Minimum inbound ports (Hetzner firewall + UFW):
- `22/tcp` (admin)
- `80/tcp`, `443/tcp` (website/API)
- `51820/udp` (WireGuard)
- `500/udp` (IKE)
- `4500/udp` (NAT-T)

## Provision
Run on VPN host as root:

```bash
bash scripts/provision_ikev2.sh
```

Optional env vars:
- `IKEV2_SERVER_IDENTITY` (DNS name recommended)
- `IKEV2_POOL_CIDR` (default `10.45.0.0/24`)
- `IKEV2_INTERFACE` (egress NIC)
- `IKEV2_DNS_1`, `IKEV2_DNS_2`
- `IKEV2_SERVER_CERT_DAYS`
- `IKEV2_CLIENT_CERT_DAYS`

## Installed Components
- `/etc/ipsec.conf`
- `/etc/ipsec.secrets`
- `/etc/securewave/secrets/ikev2/ca/` (CA DB)
- `/etc/securewave/secrets/ikev2/server-key.pem`
- `/usr/local/bin/securewave-ikev2-issue-client`
- `/usr/local/bin/securewave-ikev2-revoke-client`
- `/usr/local/bin/securewave-validate-provisioning-token`

## Backend Integration
Required backend env vars:

```bash
SECUREWAVE_IKEV2_AUTH_MODE=eap-tls
SECUREWAVE_PROVISIONING_TOKEN_SECRET=<same secret as /etc/securewave/secrets/provisioning_token_secret>
SECUREWAVE_IKEV2_CERT_VALID_DAYS=30
SECUREWAVE_PROVISIONING_TOKEN_TTL_SECONDS=300
```

`POST /api/vpn/profile` for IKEv2 returns:
- `client_pkcs12_base64`
- `client_pkcs12_password`
- `ca_cert_pem`
- `server` / `remote_id`

## Platform Client Requirements
- Windows/macOS/iOS: import P12 and trust CA cert
- Android: install P12 in user credentials and configure IKEv2/IPsec cert auth

## Validation
On VPN host:

```bash
ipsec statusall
ss -lun | rg "500|4500"
ufw status
```

From backend/API side:
- Call `POST /api/vpn/profile` with `protocol=ikev2`
- Verify `auth_method=eap-tls` and PKCS#12 fields are present

## Rotation
Run on VPN host:

```bash
SECUREWAVE_ROTATE_CONFIRM=YES bash scripts/rotate_ikev2_certs.sh
```

Effect:
- Rotates IKEv2 CA + server cert
- Previously issued client certs are invalidated

## Break Glass
1. Stop service:
```bash
systemctl stop strongswan-starter || systemctl stop strongswan
```
2. Restore latest backup from `/var/backups/securewave/ikev2-pki-*.tar.gz`
3. Restart:
```bash
systemctl start strongswan-starter || systemctl start strongswan
```
4. Revoke suspected client cert:
```bash
securewave-ikev2-revoke-client --common-name <CN>
```

## Security Notes
- Do not commit PKI artifacts.
- Restrict `/etc/securewave/secrets` to root.
- Keep Hetzner firewall restricted to required UDP ports only.
