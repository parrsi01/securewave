# SecureWave Linux Support and Certification Runbook

`master` is canonical. Run certification from a clean worktree based on updated
`origin/master` or from the focused review branch named in the certification
report. Never place credentials, raw VPN profiles, private keys, or unredacted
public/internal addresses in the repository or captured logs.

## Daily control-plane checks

```bash
curl -fsS https://api.securewaveapp.com/api/health
curl -fsS https://api.securewaveapp.com/api/ready
```

For an authorized staging deployment, also check the server health endpoint and
application/worker logs. Keep staging settings explicit (`ENVIRONMENT=staging`)
and do not allow them to fall through to production dotenv files.

## Local source and migration gates

```bash
VENV_DIR=/path/to/.venv SKIP_INSTALL=true PYTEST_ARGS='tests -q' \
  bash scripts/run_backend_tests.sh
ENVIRONMENT=development DEMO_MODE=true WG_MOCK_MODE=true \
  python -m pytest tests/integration/test_postgres_usage_concurrency.py -q
python -m alembic upgrade head
python -m alembic current
python -m alembic upgrade head
python -m alembic check
```

The PostgreSQL concurrency test requires `SECUREWAVE_TEST_POSTGRES_URL` and must
use disposable PostgreSQL, never production. A fresh migration, a repeat upgrade,
and the upgrade-path migration must all pass.

## Flutter Linux checks

```bash
cd securewave_app
dart format lib test
flutter analyze
flutter test
flutter build linux --release
```

Run the actual release binary in a desktop Linux session. Inspect narrow and
desktop screenshots for clipping, overlap, inaccessible controls, truthful
unavailable states, and recovery actions. Headless Mesa warnings are environment
diagnostics; they do not prove VPN routing.

## Package install, upgrade, and purge

For a verified local ARM64 package, first check the recorded SHA-256 and then let
`apt` resolve declared dependencies:

```bash
deb=/path/to/securewave-vpn_4.0.0+1_arm64.deb
sha256sum "$deb"
sudo apt install "$deb"
systemctl is-enabled securewave-helper.service
systemctl is-active securewave-helper.service
stat -c '%U %G %a %n' /usr/local/libexec/securewave-helperd /run/securewave/helper.sock
cat /usr/local/libexec/securewave-wg-quick.contract
```

Upgrade with `sudo apt install /path/to/securewave-vpn_NEW.deb`. After an upgrade,
repeat the service, socket, contract, and disconnected runtime checks. Purge with:

```bash
sudo apt purge securewave-vpn
test ! -e /run/securewave/helper.sock
test ! -e /usr/local/libexec/securewave-helperd
test ! -e /usr/local/libexec/securewave-wg-quick
test ! -e /usr/local/libexec/securewave-wg-quick.contract
test ! -e /etc/securewave/helper-users
```

An ARM64 package requires ARM64; an x64 GitHub artifact requires x86_64/amd64.
The x64 `.deb` remains `coming_soon` until clean VM and runtime evidence exists.

## Helper IPC and runtime cleanup

```bash
python scripts/linux_vpn_runtime_verifier.py --json
stat -c '%U %G %a %n' /usr/local/libexec/securewave-helperd /run/securewave/helper.sock
cat /usr/local/libexec/securewave-wg-quick.contract
```

The helper must be root-owned, the socket must be restricted to the explicit
`securewave` group/allowlist, and the contract must be `11`. Probe malformed and
unknown operations and verify they fail closed. After disconnect, logout, purge,
and failed connect, verify there are no tunnel interfaces, processes, routes,
DNS changes, policy rules, NetworkManager connections, or temporary profiles.

## Account and VPN lifecycle certification

Exercise registration, login, session restoration, device creation, server/profile
retrieval, connect/reconnect, key rotation, revocation, usage increments during a
session, disconnect persistence, logout/login persistence, API failures, retries,
rollback, monitoring failure/recovery, and cleanup. Use disposable accounts or
explicitly authorized staging accounts. Registration rate limits must not be
weakened to make a test pass.

## Authorized live protocol proof

Only run this section when staging credentials and infrastructure are explicitly
authorized. Capture a private baseline exit IP, then use the normal app path and
the runtime verifier once per enabled protocol:

```bash
python scripts/linux_vpn_runtime_verifier.py --skip-build-checks \
  --active-protocol wireguard --external-probes \
  --baseline-exit-ip-file /private/path/baseline-ip.txt --json
```

Require handshake/process evidence, DNS correctness, HTTPS success, endpoint
bypass, changed exit IP, counters that move, disconnect, and residue cleanup.
Repeat for OpenVPN only when backend server and data-plane evidence are usable.
Keep IKEv2 unavailable unless backend advertising and clean Linux runtime proof
both pass. Never run these probes or concurrency tests against production by
inference.

## Bounded concurrency

Use local or explicitly authorized staging only. The certified local model used
100 users, 20 workers, 100 metering events, and an abort threshold of more than
5 failures. Record the model, worker count, duration, errors, and cleanup. Scale
to 1,000 modeled users only with an explicit staging budget and abort threshold;
do not imply that a modeled metering run is production capacity proof.

## Incident and rollback

Check application/container logs, `/api/health`, `/api/ready`, server health, and
database connectivity first. Roll back to the previous known-good application
image/package and database backup according to `docs/HETZNER_RUNBOOK.md`. Do not
repair a failed VPN state by adding a direct `pkexec` or per-connect privilege
prompt; fix the helper contract or fail closed.
