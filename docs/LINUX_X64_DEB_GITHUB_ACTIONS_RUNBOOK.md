# Linux x64 Deb GitHub Actions Runbook

This runbook covers the manual x64 Debian package build-evidence workflow for
SecureWave. It is a build and package-inspection path only; it does not publish
artifacts or change public download availability.

## Workflow

Workflow file:

- `.github/workflows/linux-x64-deb-release.yml`

Trigger:

- `workflow_dispatch` only

Runner:

- `ubuntu-latest`

The workflow fails closed unless the runner reports:

- `uname -m = x86_64`
- `dpkg --print-architecture = amd64`

That makes the generated `.deb` evidence valid for Linux x64 package-build
provenance. It is not built locally on ARM64.

## Trigger the Workflow

Trigger the workflow from the reviewed branch or canonical `master` only after
the source head is identified:

```bash
gh workflow run linux-x64-deb-release.yml --ref codex/linux-runtime-final
```

Watch the run:

```bash
run_id="$(gh run list --workflow linux-x64-deb-release.yml --branch master --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run watch "$run_id"
```

If testing a branch copy before merge is available in the repository settings,
replace `master` with that branch name. Do not treat a branch test as public
release evidence until the run, commit SHA, and artifact are recorded.

## Download Evidence

Find the latest completed run:

```bash
run_id="$(gh run list --workflow linux-x64-deb-release.yml --branch master --limit 1 --json databaseId --jq '.[0].databaseId')"
```

Download the uploaded artifact bundle:

```bash
gh run download "$run_id" --dir artifacts/github-linux-x64-deb
```

Expected artifact contents include:

- `securewave-linux-x64.deb`
- `securewave-linux-x64.deb.sha256`
- `architecture.txt`
- `dpkg-architecture.txt`
- `flutter-version.txt`
- `flutter-doctor.txt`
- `build-deb.log`
- `generated-deb-path.txt`
- `package-size.txt`
- `package-file.txt`
- `package-info.txt`
- `package-contents.txt`
- `helper-payload-checks.txt`
- `package-requirements-check.txt`
- `manifest-json-check.txt`
- `manifest-x64-status.txt`
- `downloads-manifest-tests.txt` or `downloads-manifest-tests.blocked.txt`
- `README.md`

## What This Proves

The workflow proves:

- A GitHub-hosted x86_64 Ubuntu runner built the Linux `.deb`.
- The Debian package architecture is `amd64`.
- The package can be located and copied to
  `artifacts/linux-x64-deb/securewave-linux-x64.deb` inside the workflow run.
- The package has a SHA256 checksum, file metadata, Debian control metadata,
  and contents listing.
- The package contains the SecureWave app binary, desktop entry, helper daemon,
  runner helper, helper contract, systemd unit, and tmpfiles payload.
- The package declares the expected Linux VPN runtime dependencies:
  WireGuard tools, OpenVPN, NetworkManager/strongSwan packages, `iproute2`,
  `iptables`, `acl`, and `systemd`.
- The public downloads manifest remains truthful: Linux x64 `.deb` stays
  `coming_soon` until publish evidence is accepted.

## What This Does Not Prove

The workflow does not prove:

- Clean x86_64 VM installation with `dpkg -i` or `apt install -f`.
- `securewave-helper.service` starts under systemd on a clean x86_64 VM.
- `/run/securewave/helper.sock` is created and usable after install.
- Connect/disconnect works without per-connect privilege prompts.
- Live WireGuard, OpenVPN, or IKEv2 routing works.
- Runtime verifier success.
- That the `.deb` is publicly downloadable or release-ready.

Keep public claims limited to x64 build evidence until clean-VM helper proof and
live protocol proof are captured.

## Referenced historical build

The current x64 build reference for this certification pass is:

- Source head: `9243c862f08049cc583e4c94232fb44bd44f407e`
- Workflow run: `29261131617`
- Expected SHA-256:
  `c51616246415d405a45305d923332f989c0fa71c6b01ddc99ed86f3d0ea394c9`

This reference proves an x86_64 build, package metadata, helper payload, and
contract-10 packaging checks for the reviewed source head. It does not prove
clean installation, systemd socket use, or live routing. Download it only as
private evidence; the public manifest intentionally keeps the package
`coming_soon`.

```bash
rm -rf /tmp/securewave-x64-29261131617
gh run download 29261131617 \
  --dir /tmp/securewave-x64-29261131617
deb="$(find /tmp/securewave-x64-29261131617 -type f -name '*.deb' -print -quit)"
test -n "$deb"
echo "c51616246415d405a45305d923332f989c0fa71c6b01ddc99ed86f3d0ea394c9  $deb" | sha256sum -c -
dpkg-deb --field "$deb" Architecture
dpkg-deb --contents "$deb"
```

Extract and inspect the helper contract before installation:

```bash
tmp="$(mktemp -d)"
dpkg-deb -x "$deb" "$tmp"
cat "$tmp/usr/share/securewave/packaging/linux/securewave-wg-quick.contract"
rm -rf "$tmp"
```

The reviewed runtime requires contract `11`. Workflow run `29261131617` remains
historical contract-10 build evidence and is not compatible with the current
runtime. Trigger a new reviewed workflow before any clean-VM certification. Do
not promote the package or change its `coming_soon` status from build evidence
alone.

## Clean x86_64 VM certification

Use a disposable, fully updated Ubuntu/Debian VM with systemd. Take a snapshot
before install. Do not place VPN credentials in shell history, the repository,
or captured logs.

### 1. Prove architecture and package identity

```bash
test "$(uname -m)" = x86_64
test "$(dpkg --print-architecture)" = amd64
dpkg-deb --field "$deb" Architecture | grep -Fx amd64
sha256sum "$deb"
```

### 2. Install once and prove the privilege boundary

```bash
sudo apt install "$deb"
systemctl is-enabled securewave-helper.service
systemctl is-active securewave-helper.service
stat -c '%U %G %a %n' \
  /usr/local/libexec/securewave-helperd \
  /usr/local/libexec/securewave-wg-quick \
  /run/securewave/helper.sock
cat /usr/local/libexec/securewave-wg-quick.contract
```

Expected socket ownership/mode is `root securewave 660` (or fail-closed `600`
when the group is unavailable). The service and wrapper must be root-owned and
must not be group/world-writable. The current non-root test user must be in the
explicit UID allowlist; unrelated local users must not be added automatically.

Run the read-only pre-connect verifier from the exact reviewed source checkout:

```bash
python3 scripts/linux_vpn_runtime_verifier.py --skip-build-checks --json \
  > /tmp/securewave-pre-connect.json
```

Do not call this a pass if the verifier reports helper, socket, contract,
pref-220, or cleanup failures.

### 3. Authorized per-protocol proof

Only when approved test credentials and infrastructure are available:

1. Capture the pre-tunnel public IP to a private file outside the repository.
2. Connect through the normal Flutter -> MethodChannel -> helper -> backend
   profile path. A connect-time `sudo`, `pkexec`, or password prompt is a failure.
3. Run, once for each enabled protocol:

```bash
python3 scripts/linux_vpn_runtime_verifier.py \
  --skip-build-checks \
  --active-protocol wireguard \
  --external-probes \
  --baseline-exit-ip-file /private/path/baseline-ip.txt \
  --json > /tmp/securewave-wireguard-active.json
```

Repeat with `openvpn` and `ikev2` only if the helper probe and backend profile
both advertise them. IKEv2 must fail if XFRM ESP evidence is absent or an
unqualified pref-220 loop rule is present. The verifier output redacts public
addresses and counter values.

4. Disconnect through the app and rerun the disconnected verifier. No process,
   interface, route, DNS, policy-table, pref-220, or NetworkManager VPN residue
   may remain.

### 4. Uninstall and cleanup

```bash
sudo apt purge securewave-vpn
test ! -e /run/securewave/helper.sock
test ! -e /usr/local/libexec/securewave-helperd
test ! -e /usr/local/libexec/securewave-wg-quick
test ! -e /usr/local/libexec/securewave-wg-quick.contract
test ! -e /etc/securewave/helper-users
systemctl is-active securewave-helper.service && exit 1 || true
```

Record package checksum, commit, VM image/version, architecture, install result,
redacted verifier JSON, no-prompt observation, protocol result, disconnect
cleanup, and purge result. Keep raw configs, private keys, credentials, public
or internal IP addresses, and unredacted journals out of evidence.

## Later Publish PR

After evidence is accepted:

1. Download the artifact bundle with `gh run download`.
2. Verify the SHA256 checksum locally on a clean machine.
3. Install the `.deb` on a clean x86_64 Debian/Ubuntu/systemd VM.
4. Capture helper service, socket, contract, launch, uninstall, and runtime
   verifier evidence.
5. Run live WireGuard/OpenVPN/IKEv2 proof if credentials and authorization are
   available.
6. Open a separate publish PR that adds the accepted artifact to the intended
   download location and updates `static/downloads/manifest.json`.

Do not update the manifest from `coming_soon` in the workflow PR.
