# Verification commands

Run from the repository root:

```bash
.venv/bin/python -m compileall -q main.py routes services utils models scripts
.venv/bin/python -m pytest -q tests
(cd securewave_app && flutter analyze && flutter test)
./scripts/build_linux_deb.sh
./scripts/verify_linux_deb.sh securewave_app/build/packaging/securewave-vpn_<version>_<arch>.deb
```

These checks are local and non-destructive. They do not install a package,
alter a host, contact the public API, use live credentials, deploy, publish,
push, or merge.

Live acceptance is separate: clean-device install, real account, authenticated
peer registration, WireGuard handshake, egress movement, reconnect, restart,
disconnect, and residue cleanup all require current external evidence.
