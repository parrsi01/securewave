# IKEv2 Hetzner runtime runbook

IKEv2 is a Linux-only, fail-closed SecureWave path. It is not enabled by a
local `swanctl` installation, a server inventory flag, a generated profile, or
an interface appearing in `ip link`. API/UI availability requires current,
authenticated control-plane evidence and fresh data-plane evidence for the
specific selected server. The app reports connected only after the contract-13
helper validates kernel evidence and the backend accepts a post-tunnel HTTPS
egress movement proof.

## Architecture

The client uses NetworkManager's strongSwan plugin (`network-manager-strongswan`
and `strongswan-nm`). The Flutter process calls only the allowlisted
`/run/securewave/helper.sock`; it does not invoke `sudo`, `pkexec`, `nmcli`, or
strongSwan tools itself. The root helper writes the fixed `SecureWave-IKEv2`
NetworkManager profile and uses `charon-nm` with:

- XFRM interface `nm-xfrm-sw`;
- routing table and priority `210`;
- outer ESP mark `0xdc` (220);
- a `not fwmark 0xdc` table-210 policy rule; and
- a tagged public-IPv6 block while the IPv4 tunnel is active.

`pref 220 from all lookup 220` (or `table 220`) is a legacy routing loop. The
helper and verifier reject it. They never remove it automatically because it
may belong to an unrelated host IPsec setup. SecureWave cleanup removes only
its NetworkManager profile, table-210 state, `nm-xfrm-sw`, root-owned runtime
records, SecureWave IPv6 rule, DNS state, and profile-local CA/config files.

Each API profile receives an opaque `swikev2-...` EAP-MSCHAPv2 identity and a
short-lived random secret scoped to one user, device, and server. The backend
encrypts the secret at rest; the gateway receives it over authenticated SSH
stdin and stores it only in root-readable swanctl fragments. Rotation/revocation
deactivates the previous remote identity before the database state is committed.

## Dedicated gateway provisioning

Only use a freshly selected, explicitly authorized Hetzner gateway. The script
refuses a shared strongSwan installation: it reloads credentials with
`swanctl --load-all --clear`, which is safe only when SecureWave is the sole
gateway owner. It installs `charon-systemd`, `strongswan-swanctl`, EAP support,
an EAP-MSCHAPv2 responder, a private IPv4 pool, root-only credential helpers,
and tagged forwarding/NAT rules. It does not change API availability.

Open UDP 500 and 4500 in the explicitly selected Hetzner firewall first. Then,
on that gateway only:

```bash
sudo infrastructure/hetzner/provision_ikev2_server.sh \
  --public-host vpn.example.com --dns 94.140.14.14 --pool 10.77.0.0/24
sudo infrastructure/hetzner/provision_ikev2_server.sh --print-ca \
  > /secure/operator-only/securewave-ikev2-ca.pem
```

`--public-host` is both the certificate identity and the value supplied as
`--ikev2-remote-id`. Keep the CA export operator-local. Never copy the CA
private key, server private key, EAP fragment, profile, API token, SSH key, or
egress-evidence secret into this repository, CI logs, support bundle, or chat.

The server exposes only these fixed SSH/sudo commands to the configured
automation account:

- `/usr/local/libexec/securewave-ikev2-health`
- `/usr/local/libexec/securewave-ikev2-credential upsert <opaque-id>`
- `/usr/local/libexec/securewave-ikev2-credential revoke <opaque-id>`

The secret for `upsert` is read from standard input, not an argument or log.
There is no VICI, `ipsec`, shell, or arbitrary command API exposed to the
backend.

## Inventory and health gates

Set backend secrets in the explicitly authorized environment, including a
unique 32+ character `SECUREWAVE_EGRESS_EVIDENCE_SECRET`, plus SSH credentials
for the gateway health/credential channel. Pin the selected gateway host key in
a backend-readable file owned by the service account and not writable by group
or others, then set `SECUREWAVE_IKEV2_SSH_KNOWN_HOSTS_PATH` to that path.
IKEv2 refuses health checks and credential writes without this pin. Register
only the public CA and certificate identity after provisioning:

```bash
python3 infrastructure/hetzner/sync_vpn_servers.py \
  --fetch-wg-public-key --supports-ikev2 \
  --ikev2-remote-id vpn.example.com \
  --ikev2-ca-cert-path /secure/operator-only/securewave-ikev2-ca.pem
```

The sync command rejects missing/unsafe identities, missing CA material, and
private-key input. It still does not enable IKEv2. The health monitor must first
record a successful authenticated gateway probe; an authorized client flow must
then record fresh matching data-plane evidence. A failed, stale, future-dated,
unauthenticated, or missing observation leaves the protocol unavailable.

Use the read-only fleet audit to inspect redacted state:

```bash
python3 infrastructure/hetzner/audit_vpn_fleet.py --json-out /tmp/securewave-fleet-audit.json
```

For IKEv2, inspect `dedicated_gateway`, `helpers_present`,
`authenticated_health`, both UDP ports, SecureWave certificate paths, and the
tagged NAT result. Audit output is diagnostic only; it is not data-plane proof.

## Required client evidence

Before a UI connection is accepted, the helper requires an active exact
NetworkManager profile, `nm-xfrm-sw`, the persisted XFRM if-id, table-210
default routing, IPv6 block, tunnel DNS, matched ESP/XFRM state and policy,
safe policy rules, and endpoint bypass. The endpoint must be a canonical
numeric address embedded both as `remote_addrs` and `# endpoint_ip`; a profile
cannot redirect IKE traffic elsewhere.

After helper evidence, the Flutter client sends the normal authenticated HTTPS
egress check. It must observe changed source egress that matches the selected
server without returning an address to the UI. It then starts or resumes usage
metering. Failed egress validation disconnects and deletes the ephemeral IKEv2
profile/CA material.

For explicitly authorized staging only, capture a private baseline then run:

```bash
python3 scripts/linux_vpn_runtime_verifier.py --skip-build-checks \
  --active-protocol ikev2 --external-probes \
  --baseline-exit-ip-file /secure/operator-only/baseline-ip.txt --json
```

Require IPv4/IPv6 endpoint bypass, safe policy routing, IKE/ESP/XFRM evidence,
DNS, HTTPS, changed exit IP, usage/counter evidence, reconnect/rekey, helper
restart, failed-connect rollback, disconnect, and residue cleanup. Never run
this command against production by inference. In the absence of authorization,
use the isolated lab described by the checked-in
[`ikev2_container_lab.sh`](../scripts/ikev2_container_lab.sh) script and keep
availability unchanged. It exercises a private gateway/client/egress topology;
it does not constitute a public exit-IP, NetworkManager-helper, or authorized
staging proof.

## Support and rollback

Collect only redacted helper/verifier fields, for example:

```bash
python3 scripts/linux_vpn_runtime_verifier.py --skip-build-checks --active-protocol ikev2 --json
python3 scripts/linux_vpn_runtime_verifier.py --skip-build-checks --check-residue --json
```

Do not attach swanctl configuration, EAP fragments, CA/private keys, profiles,
tokens, or raw addresses to support tickets. On an app failure, use the normal
disconnect operation first. If it cannot verify cleanup, preserve the block,
record the redacted failure state, and escalate; do not delete a pref-220/table-
220 rule or restart a system strongSwan daemon without an approved maintenance
window.

IKEv2 remains unavailable until the exact source revision has all required
backend, package, and authorized runtime evidence.
