# Linux Multi-Architecture Packaging

SecureWave Linux Debian packages must be built and proven on matching
architectures. Do not use an ARM64 host to claim x64 package truth.

## Current Truth

- Local ARM64 packaging is valid on an `aarch64` / Debian `arm64` machine.
- x64 Debian package evidence must come from an x86_64 / Debian `amd64`
  environment, such as GitHub Actions `ubuntu-latest`.
- GitHub-hosted Linux ARM64 runner labels are available in GitHub's runner docs,
  including `ubuntu-24.04-arm`, but they may still depend on repository or
  account runner availability.
- Workflow artifacts are build evidence only. They are not public release
  downloads and do not change `static/downloads/manifest.json`.

## Local ARM64 Build Path

Run this only on an ARM64 Linux host:

```bash
uname -m
dpkg --print-architecture
bash -n securewave_app/scripts/build_deb.sh
cd securewave_app
bash scripts/build_deb.sh
cd ..
```

Expected host truth:

```text
uname -m -> aarch64
dpkg --print-architecture -> arm64
```

Expected local package shape:

```text
securewave_app/build/packaging/securewave-vpn_<version>_arm64.deb
```

This local package is evidence only until install/service/socket proof passes.
Do not copy it into `static/downloads` or mark a manifest entry available from
the build step alone.

## GitHub Actions x64 Build Path

Use the manual workflow:

```text
Actions -> Linux Debian Package Evidence -> Run workflow
architecture: x64
```

The x64 path runs on `ubuntu-latest` and fails closed unless:

```text
uname -m == x86_64
dpkg --print-architecture == amd64
```

The workflow builds with `securewave_app/scripts/build_deb.sh`, then normalizes
the uploaded package name to:

```text
securewave-linux-x64.deb
```

The workflow uploads an evidence bundle containing:

- `securewave-linux-x64.deb`
- `securewave-linux-x64.deb.sha256`
- `securewave-linux-x64.deb.dpkg-info.txt`
- `securewave-linux-x64.deb.dpkg-contents.txt`
- `securewave-linux-x64.deb.file.txt`
- `evidence-summary.md`

The workflow does not commit artifacts, publish downloads, update release pages,
or mark manifest entries available.

## GitHub Actions ARM64 Build Path

Use the same workflow with:

```text
architecture: arm64
```

The ARM64 path targets `ubuntu-24.04-arm` and fails closed unless:

```text
uname -m == aarch64
dpkg --print-architecture == arm64
```

The normalized uploaded package name is:

```text
securewave-linux-arm64.deb
```

If the repository cannot access `ubuntu-24.04-arm`, treat ARM64 GitHub Actions
evidence as blocked and use the local ARM64 build path instead.

## Why x64 Cannot Be Proven On ARM64

`securewave_app/scripts/build_deb.sh` uses the host Debian architecture from:

```bash
dpkg --print-architecture
```

On this VM that returns `arm64`, so the package is ARM64. A file copied or
renamed to an x64 filename from this machine would still contain ARM64 binaries.
That is not x64 evidence.

## What Counts As Build Evidence

Build evidence requires all of these:

- Matching host architecture checks (`uname -m` and `dpkg --print-architecture`)
- Successful `securewave_app/scripts/build_deb.sh`
- `dpkg-deb --field <package> Architecture` matches the requested architecture
- `dpkg-deb --info` is captured
- `dpkg-deb --contents` is captured
- SHA256 checksum is captured
- Required helper payload is present:
  - `securewave-helperd`
  - `securewave-wg-quick`
  - `securewave-wg-quick.contract`
  - `securewave-helper.service`
  - `securewave-helper.tmpfiles`
  - `securewave-helper.conf`
- Runtime package dependencies are present in the `.deb` `Depends` field

Build evidence proves package construction only. It does not prove the package
can be promoted as a public download.

## Clean VM Install Proof Still Required

Before any artifact-publish PR, run a clean Debian/Ubuntu systemd VM proof on
the same architecture as the package:

```bash
sudo dpkg -i ./securewave-linux-<arch>.deb
sudo apt-get install -f -y
systemctl status securewave-helper.service --no-pager
test -S /run/securewave/helper.sock
cat /usr/local/libexec/securewave-wg-quick.contract
command -v securewave-vpn
sudo apt-get remove -y securewave-vpn
```

For x64, this must run on a clean `x86_64` / Debian `amd64` VM. For ARM64, this
must run on a clean `aarch64` / Debian `arm64` VM.

Full VPN routing is a separate runtime proof. Do not claim full routing from
package build evidence alone.

## Downloading Workflow Artifacts

After the workflow completes:

1. Open the workflow run in GitHub Actions.
2. Download the `securewave-linux-deb-<arch>-<run_id>` artifact.
3. Verify the `.sha256` file locally.
4. Review `evidence-summary.md`, `.dpkg-info.txt`, and `.dpkg-contents.txt`.
5. Keep the artifact out of `static/downloads` until publish proof is complete.

## Later Artifact-Publish PR

Create a separate publish PR only after matching clean VM install proof exists.
That PR should:

- Add the proven `.deb` artifact under the intended download path.
- Add or update checksum metadata.
- Update `static/downloads/manifest.json` only for artifacts that exist and are
  proven.
- Include the workflow run URL, SHA256, `dpkg-deb --info`, `dpkg-deb --contents`,
  clean VM install proof, helper service proof, socket proof, launch proof, and
  uninstall cleanup proof.
- Keep x64 and ARM64 evidence separate.
