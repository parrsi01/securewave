# Hetzner WireGuard target

Beta 1 uses one Hetzner Linux host as its only production data plane. The API
stores one `VPNServer` row selected by `WIREGUARD_SERVER_ID`; the client never
sees a server list or region picker.

## Host

Provision a single Hetzner Linux host, install WireGuard, enable IP
forwarding and forwarding/NAT for the client subnet, and expose only the
required SSH and WireGuard UDP ports. Keep the server private key on the host.

The repository includes the starting host script:

```bash
ssh root@<server-ip> 'bash -s' < infrastructure/wireguard_vm_setup.sh
```

Record only the server public key, endpoint, location label, and health state in
the backend database. Do not commit keys or generated client profiles.

## Backend configuration

Production requires:

```text
ENVIRONMENT=production
DATABASE_URL=postgresql+psycopg2://...
ACCESS_TOKEN_SECRET=<secret-store value>
WG_ENCRYPTION_KEY=<secret-store value>
WIREGUARD_SERVER_ID=<the single active row>
WG_SSH_USER=securewave
WG_SSH_KEY_PATH=<private key path>
WG_KNOWN_HOSTS_PATH=<root-owned pinned known-hosts file>
```

The backend confirms peer registration over the authenticated SSH path before
returning a private-key-bearing profile. Missing key material, a missing
known-hosts file, or a target that rejects the peer fails closed.

## Acceptance

Before calling the beta live, prove all of these on a clean ARM64 Linux device:

1. Install the exact `.deb` and verify its checksum.
2. Register and log in with a real account.
3. Connect and observe a recent WireGuard handshake.
4. Confirm public egress moves through the Hetzner host.
5. Disconnect and verify interface, routes, firewall state, and DNS cleanup.
6. Reconnect and cold-launch again.

This runbook does not deploy or publish anything. Production changes require
an explicit operator action outside local certification.
