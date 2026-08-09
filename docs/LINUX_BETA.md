# SecureWave Linux beta

This branch keeps the Linux path intentionally small: email/password account
authentication, authenticated API requests, WireGuard server/profile retrieval,
and the native WireGuard helper. OpenVPN, IKEv2, payments, email delivery, and
release publishing are deferred.

## Configure and run

The release API is `https://api.securewaveapp.com/api`. Override it explicitly
for a test backend:

```bash
export SECUREWAVE_API_BASE_URL=https://api.example.test/api
./scripts/run_linux_beta.sh flutter
```

For a local backend, configure the repository's normal database environment,
then run:

```bash
./scripts/run_linux_beta.sh backend
```

The backend defaults to `127.0.0.1:8001`; the Flutter runner uses the live API
default unless `SECUREWAVE_API_BASE_URL` is set.

## Test and package

```bash
./scripts/test_linux_beta.sh
./scripts/build_linux_deb.sh
./scripts/verify_linux_deb.sh securewave_app/build/packaging/securewave-vpn_<version>_<arch>.deb
```

The package contains the Flutter release bundle and the root-owned systemd
WireGuard helper payload. Installation requires a compatible system with
`wireguard-tools`, `iproute2`, `iptables`, `nftables`, systemd, and
`systemd-resolved`. Connect/disconnect does not request administrator
credentials; the package installer performs the one-time privileged setup.

The read-only host verifier is:

```bash
.venv/bin/python scripts/linux_vpn_runtime_verifier.py --skip-build-checks
```

An active-tunnel proof additionally needs an authorized account, a real
WireGuard peer, and an explicit baseline exit-IP file:

```bash
.venv/bin/python scripts/linux_vpn_runtime_verifier.py \
  --skip-build-checks \
  --active-protocol wireguard \
  --external-probes \
  --baseline-exit-ip-file /path/to/private/baseline-ip.txt
```

The verifier never starts or stops a tunnel and never prints secrets or IP
addresses.
