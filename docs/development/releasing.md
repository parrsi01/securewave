# Build and release procedure

The source version is **1.0.0**. Compatibility identifiers remain helper
contract **15**, request protocol **1**, and usage protocol **2**.

## Build environment

Ubuntu 24.04 ARM64, Flutter 3.41.4/Dart 3.11.1, clang, CMake, Ninja, pkg-config,
GTK3 and Secret Service headers, Debian packaging tools and WireGuard runtime
tools are required. Install native development dependencies with Ubuntu's
package manager; `scripts/prepare_flutter_env.sh` describes the repository's
toolchain setup. Build commands are in
[`build_deb.sh`](../../securewave_app/scripts/build_deb.sh).

## Exact-source candidate

Commit reviewed changes on master, run relevant checks and create a disposable
detached checkout of that exact commit. Confirm a clean source tree before the
build, then run:

```sh
cd securewave_app
bash scripts/build_deb.sh
```

Output is `build/packaging/securewave-vpn_1.0.0_arm64.deb` plus checksum and
source sidecars. Extract into a temporary directory with `dpkg-deb -x` and
verify `/usr/share/securewave/release/`: source-sha, source-tree-state,
app-version, package-architecture and helper-contract. Verify Debian metadata
and ARM64 ELF architecture separately. Check the source tree after building.

## Installed transition

1. Record the currently installed package and disconnect any active tunnel.
2. Review the exact candidate and its provenance.
3. Install the package on an authorized device. A 4.0.0+… to 1.0.0 transition
   is a downgrade in Debian ordering; unattended tooling may require an
   explicit downgrade option.
4. Verify daemon/reporter services, socket, cold launch and authenticated
   Connect/Disconnect/Reconnect with real traffic and final usage history.
5. Reboot, verify new boot identity and repeat the installed acceptance gates.

Building a candidate does not change an already installed package. A source
rename also does not replace the public download or its original metadata.

## GitHub and public delivery

Keep master as the sole branch; use an immutable candidate tag for release
assets. A historical `v1.0.0` tag already exists and must not be moved silently.
Use a distinct candidate tag until an explicit release decision is made.
Preserve earlier 4.0.0+… assets as historical records.

A draft GitHub asset is a saved candidate. Public website publication is a
separate action after exact-source, installed lifecycle and reboot evidence.
Recheck catalog, actual downloadable bytes, checksum and source marker before
claiming public availability. Production configuration and database migration
require their own protected environment and operational procedure.
