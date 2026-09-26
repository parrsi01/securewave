# Do not lose

This is a source inventory of the existing production and Linux WireGuard boundaries. It contains configuration names only, never secret values.

- **API:** main.py registers routes/auth.py and routes/vpn.py. The production API base is https://api.securewaveapp.com/api.
- **Database:** database/session.py connects through server-side DATABASE_URL. Production PostgreSQL data and schema are outside this Flutter change. Flutter has no database driver or credentials.
- **Hetzner:** production VPN hosts and their current deployment are infrastructure state. Relevant provisioning code is under infrastructure/; do not reprovision or replace it during a client rebuild.
- **WireGuard server:** infrastructure/wireguard_vm_setup.sh manages the server-side wg0 setup and /etc/wireguard/wg0.conf. Keep deployed keys, peers, firewall, routes, and DNS configuration unchanged.
- **Auth contract:** POST /api/auth/register (email, password, password_confirm) and POST /api/auth/login return bearer tokens; GET /api/auth/me validates a session; POST /api/auth/logout invalidates the token generation. Registration does not require email verification.
- **VPN API contract:** GET /api/vpn/protocols reports WireGuard availability; POST /api/vpn/profile creates or reuses a peer and returns its WireGuard configuration. POST /api/vpn/connect and POST /api/vpn/disconnect record client session state. Usage reporting uses POST /api/vpn/usage/sessions/start, POST /api/vpn/usage/sessions/{session_id}/increment, and POST /api/vpn/usage/sessions/{session_id}/disconnect.
- **Linux privilege boundary:** Flutter's securewave/vpn method channel is implemented in securewave_app/linux/runner/my_application.cc. The root-owned daemon is securewave_app/linux/helperd/securewave_helperd.cc; it accepts operations over /run/securewave/helper.sock and invokes the packaged securewave-wg-quick.
- **Privilege policy:** the securewave-helper.service systemd unit, securewave-helper.tmpfiles, securewave group, and /etc/securewave/helper-users allowlist define local access. No active polkit policy is required; install_linux_helper.sh removes the legacy 50-securewave-wg.rules file.
- **Tunnel and counters:** runner methods connect/disconnect send wireguard.up/wireguard.down to the helper. getStatus reads wireguard.status; getTrafficStats reads wireguard.counters with status-counter fallback. Client receive bytes are download; transmit bytes are upload.
- **Client configuration:** SECUREWAVE_API_BASE_URL selects the API base for local runs/builds and defaults to the production API. Database, token-signing, WireGuard encryption, SSH, and server-management credentials remain server-side and must never be copied into Flutter or this inventory.
