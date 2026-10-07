# Testing and acceptance

Install Python 3.12 requirements from `requirements-dev.txt`. Native checks need
g++, pkg-config and GLib/GIO development headers. Flutter checks use 3.41.4
stable and the committed pubspec lockfile.

```sh
make test-backend
make test-flutter
make test-native
make check
```

Use `make PYTHON=/path/to/venv/bin/python test-backend` when a virtual
environment is not activated. Python tests create disposable fixtures. Native
tests build a temporary executable and simulate approved commands; they do not
invoke the installed daemon or change host routes.

For optional routing research, install `requirements-ml.txt`, then run:

```sh
python -m pytest --confcutdir=tests -q tests/test_routing_training.py \
  tests/test_routing_shadow.py tests/test_routing_worker.py \
  tests/test_routing_collection.py tests/test_routing_integration.py
python -m ml.train_routing --output /var/tmp/securewave-routing-model \
  --seed 42 --episodes 80
```

The core API imports no native ML libraries. Heavy training/worker tests skip
explicitly when their optional dependencies are absent; CI has a separate job
that installs them. See the [routing guide](routing-optimizer.md) for measured
input provenance, fail-open tests, model hashes and evaluation limits.

## Real PostgreSQL

Two tests require PostgreSQL: simultaneous identical cumulative checkpoints
and additive migration of a legacy-shaped schema. Configure
`SECUREWAVE_TEST_DATABASE_URL` locally to a dedicated disposable database before
`make test-backend`. The migration test deliberately drops test columns; never
point this variable at production, a shared development database or retained
data. CI supplies a disposable PostgreSQL 16 service automatically. Without the
variable, these tests are skipped explicitly.

## Flutter and native coverage

The Flutter suite covers API/session behavior, WireGuard runtime validation,
usage contracts, keyboard/focus behavior, viewport/text scaling and golden
fixtures. Goldens depict known state; they do not prove an actual connection.
Native cases cover constrained helper requests, ownership, safe configuration,
durable accounting, acknowledgement and cleanup.

## Installed post-reboot workflow

The harness uses system Python with PyGObject, AT-SPI, GDK/X11 and an accessible
installed SecureWave window. It assumes exactly one app window, the supported
Linux helper, `ip`, `resolvectl` and `curl`. X11 compatibility can be selected
for the installed GUI with `GDK_BACKEND=x11 GTK_A11Y=1`. It stores screenshots
and network evidence in an existing mode-0700 directory.

```sh
install -d -m 0700 /var/tmp/securewave-acceptance-local
/usr/bin/python3 scripts/securewave_post_reboot_acceptance.py \
  --evidence-dir /var/tmp/securewave-acceptance-local initialize
```

After signing in privately in the app, use the `lifecycle` operation with the
same evidence directory. It executes Connect, bounded traffic, Disconnect,
Reconnect and final Disconnect, checking helper/peer/handshake/counters,
route/DNS/egress and baseline restoration. The `register` operation creates a
live disposable account and is used only when explicitly authorized.

The lifecycle harness does not independently close the final production-ledger
gate. A companion
[`securewave_usage_history_acceptance.py`](../../scripts/securewave_usage_history_acceptance.py)
is prepared to check owner-scoped history. After private sign-in, run its
`before` operation with the same `--evidence-dir`, run the lifecycle harness,
then run its `after` operation. It checks two new finalized version-2 sessions,
complete quality, verification timestamps and totals covering independently
observed traffic. It uses the installed app's account token only in process
memory through libsecret, refuses redirects, and stores only permitted history
fields. The desktop also needs `gir1.2-secret-1`. The verifier passed live
owner-scoped history checks for the installed 1.0.0 test on 6 October 2026.

Retain raw evidence privately; publish a redacted result tied to package/source
identity. The 1.0.0 installation, baseline, authenticated lifecycle and final
usage-history checks passed; an additional boot with 1.0.0 installed remains open. See
[current state](../current-state.md).
