# SecureWave NetOps Daemon

`securewave-netd` is the privileged Linux-side networking daemon for SecureWave.

Build it from the repo root with:

```bash
bash ./scripts/build_netopsd.sh
```

For non-root execution, the daemon binary must carry `cap_net_admin+eip` so
the daemon can raise `CAP_NET_ADMIN` into ambient capabilities for its child
`ip`, `wg`, `iptables`, and `sysctl` commands.

Apply the capability on one line:

```bash
sudo setcap cap_net_admin+eip /home/sp/cyber-course/projects/securewave/netopsd/bin/securewave-netd
```

Runtime socket behavior:

- root default: `/run/securewave/netops.sock`
- non-root default with `XDG_RUNTIME_DIR`: `$XDG_RUNTIME_DIR/securewave/netops.sock`
- non-root fallback: `/tmp/securewave-<uid>/netops.sock`

Override explicitly when needed:

```bash
SECUREWAVE_NETOPSD_SOCKET_PATH="$XDG_RUNTIME_DIR/securewave/netops.sock" ./netopsd/bin/securewave-netd
```

Responsibilities:

- Unix domain socket JSON RPC server
- allowlisted privileged networking operations
- WireGuard interface lifecycle and configuration
- routing/policy routing changes
- NAT rule setup/teardown
- cleanup hooks for VPN-owned state

Non-responsibilities:

- authentication
- billing
- subscription enforcement
- user/device authorization
- API routing
- plan logic

The Python/FastAPI backend decides **what** operation is authorized and needed.
This daemon decides **how** to execute the privileged OS mutation safely.
