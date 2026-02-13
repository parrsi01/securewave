# Server Key Lifecycle

## Overview
Server WireGuard keys are stored in `vpn_servers` with:
- `wg_public_key`
- `wg_private_key_encrypted`
- `wg_key_version`
- `wg_last_rotated_at`
- `wg_next_rotation_at`

Private keys are encrypted using `WG_ENCRYPTION_KEY`.

## Seed a node
```bash
./securewave vpn seed add-node \
  --server-id hel1-01 \
  --location "Helsinki" \
  --country Finland \
  --country-code FI \
  --city Helsinki \
  --hcloud-location hel1 \
  --public-ip 203.0.113.10 \
  --wg-public-key <BASE64_KEY>
```

## Rotate server key
Database-only rotation:
```bash
./securewave vpn rotate server-key --server-id hel1-01
```

Remote+database rotation over SSH:
```bash
./securewave vpn rotate server-key \
  --server-id hel1-01 \
  --apply-remote \
  --ssh-user securewave \
  --ssh-key-path /home/securewave/.ssh/id_rsa
```

When remote apply is enabled, the rotation process includes rollback safeguards
if `wg-quick@wg0` fails to restart.
