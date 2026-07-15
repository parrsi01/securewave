# OpenVPN Hetzner runtime runbook

OpenVPN is a Linux protocol. It remains unavailable until backend runtime health and independent data-plane evidence are fresh; provisioning a host or finding a local `openvpn` binary is never sufficient.

Run the checked-in provisioning script only as root on an explicitly authorized Hetzner server:

```bash
sudo infrastructure/hetzner/provision_openvpn_server.sh --public-host vpn.example.com --transport udp
```

The CA and server private keys stay under `/etc/securewave/openvpn` on that host. The script never prints private material. Retrieve only the public CA using `--print-ca`, then perform the controlled fleet-sync flow and record compact, redacted runtime and external data-plane evidence.

The server exposes fixed-command health and credential utilities through authenticated SSH; it has no public management interface. Credentials are opaque, per-device, short lived, revocable, and stored as salted verifiers on the server. The server assigns IPv6 addresses itself; client profiles never hard-code a shared IPv6 address. The current client contract intentionally blocks public IPv6 inside the OpenVPN tunnel rather than risking a physical-link leak, so it does not claim OpenVPN IPv6 exit capability. Stopping `securewave-openvpn-nat.service` removes only `SECUREWAVE_OPENVPN_FORWARD`, `SECUREWAVE_OPENVPN6_FORWARD`, and NAT rules tagged `securewave-openvpn-v*-v1`.

Before enabling this protocol in an authorized environment, configure a unique `SECUREWAVE_EGRESS_EVIDENCE_SECRET` of at least 32 printable characters in the backend secret store. When the app is behind a reverse proxy, set `SECUREWAVE_TRUSTED_PROXY_CIDRS` only to that proxy's private network. OpenVPN connects only after a post-tunnel authenticated HTTPS request both changes its redacted egress fingerprint and matches the selected server public IP. Missing proxy configuration, a mismatched source, or a failed request leaves the protocol unavailable or rolls the tunnel back; no address is returned to the client or logs.
