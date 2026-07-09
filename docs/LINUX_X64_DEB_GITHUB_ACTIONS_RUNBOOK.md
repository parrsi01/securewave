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

After the workflow is merged to `master`, trigger it with:

```bash
gh workflow run linux-x64-deb-release.yml --ref master
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
