# SecureWave NetOps Daemon

`securewave-netd` is the privileged Linux-side networking daemon for SecureWave.

Build it from the repo root with:

```bash
bash ./scripts/build_netopsd.sh
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
