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
gh workflow run linux-x64-deb-release.yml --ref <exact-release-branch>
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
- The package declares only the WireGuard Linux runtime dependencies:
  `wireguard-tools`, `iproute2`, `iptables`, `nftables`, `acl`, `systemd`, and
  `systemd-resolved`.
- The public downloads manifest remains truthful: Linux x64 `.deb` stays
  `coming_soon` until publish evidence is accepted.

## Evidence boundary

On a green current run, the workflow proves the package on an ephemeral
GitHub-hosted x86_64 Ubuntu runner: amd64 ELF payloads, contract 13, declared
dependencies, install, systemd helper/socket state, structural verifier,
bounded application launch, purge, and SecureWave-owned network residue checks.
It does not prove:

- Clean x86_64 VM installation with `dpkg -i` or `apt install -f`.
- Connect/disconnect with a real authenticated staging profile.
- Live WireGuard routing, DNS, HTTPS, exit-IP, handshake, or counter evidence.
- That the `.deb` is publicly downloadable or release-ready.

Keep public claims limited to private beta/build-and-lifecycle evidence until
the exact source revision also has authorized live protocol proof.

## Record private workflow evidence

For the exact reviewed head, record:

- full source SHA embedded in the package;
- workflow run URL;
- independently verified package SHA-256.

The accepted run must pass amd64 ELF and contract-13 checks, dependency and helper payload
checks, ephemeral install/service/socket verification, structural verifier,
bounded application launch, purge, and SecureWave-owned networking residue
checks. Keep the artifact private: live authenticated WireGuard data-plane proof
is still required.

## Superseded evidence

Pre-contract-13 package evidence is intentionally excluded from this runbook.
It is not compatible with the current helper/runtime and must not be downloaded,
installed, or used for release decisions. Trigger this workflow on the exact
current exact release head and record only that artifact's source
SHA, checksum, and lifecycle evidence.

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
charon-nm table-210, or cleanup failures.

### 3. Authorized per-protocol proof

Only when approved test credentials and infrastructure are available:

1. Capture the pre-tunnel public IP to a private file outside the repository.
2. Connect through the normal Flutter -> MethodChannel -> helper -> backend
   profile path. A connect-time `sudo`, `pkexec`, or password prompt is a failure.
3. Run the WireGuard verifier:

```bash
python3 scripts/linux_vpn_runtime_verifier.py \
  --skip-build-checks \
  --active-protocol wireguard \
  --external-probes \
  --baseline-exit-ip-file /private/path/baseline-ip.txt \
  --json > /tmp/securewave-wireguard-active.json
```

OpenVPN and IKEv2 are not enabled for Linux v1 and must remain unavailable or
Coming soon. The verifier output redacts public addresses and counter values.

4. Disconnect through the app and rerun the disconnected verifier. No process,
   interface, route, DNS, charon-nm table-210 route, ESP-template policy, or
   NetworkManager VPN residue may remain. An exact paired table-210 rule is
   allowed only as idle daemon infrastructure.

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
5. Run live WireGuard proof if credentials and authorization are available.
6. Open a separate publish PR that adds the accepted artifact to the intended
   download location and updates `static/downloads/manifest.json`.

Do not update the manifest from `coming_soon` in the workflow PR.
