# SecureWave Linux WireGuard prerelease tester runbook

This runbook supports Ubuntu/Debian systemd hosts on `amd64` and `arm64` only.
It does not claim universal Linux support. AppImage, tar, and zip builds are
UI-only unless the matching certified contract-13 helper is installed.

Use only an explicitly authorized staging API. Never paste passwords, tokens,
profiles, private keys, complete addresses, or secret environment values into
feedback. Do not test production with this runbook.

## 1. Record the platform and select the package

```bash
. /etc/os-release
printf 'distribution=%s version=%s\n' "$ID" "$VERSION_ID"
dpkg --print-architecture
ldd --version | head -n 1
ps -p 1 -o comm=
printf 'session=%s desktop=%s\n' "${XDG_SESSION_TYPE:-unknown}" "${XDG_CURRENT_DESKTOP:-unknown}"
```

Continue only for Ubuntu/Debian with systemd and `amd64` or `arm64`. Select the
`.deb` whose architecture exactly equals `dpkg --print-architecture`. Reject
`amd64` on `arm64`, `arm64` on `amd64`, all other architectures, and hosts
without systemd.

Set the package and release-provided checksum without putting credentials in
the shell:

```bash
PACKAGE=./securewave-vpn_VERSION_ARCH.deb
EXPECTED_SHA256='release-provided-64-hex-digest'
test "$(dpkg --print-architecture)" = "$(dpkg-deb --field "$PACKAGE" Architecture)"
test "$(sha256sum "$PACKAGE" | awk '{print $1}')" = "$EXPECTED_SHA256"
dpkg-deb --field "$PACKAGE" Package Version Architecture Depends
```

Stop on any mismatch.

## 2. Install and validate the privileged runtime

```bash
sudo apt install "$PACKAGE"
systemctl is-enabled securewave-helper.service
systemctl is-active securewave-helper.service
systemctl show securewave-helper.service --property=LoadState,ActiveState,SubState,UnitFileState
sudo stat -c 'owner=%U group=%G mode=%a type=%F' /run/securewave/helper.sock
cat /usr/local/libexec/securewave-wg-quick.contract
```

Expected: active/enabled service, socket `root:securewave` mode `660`, and
contract exactly `13`. Confirm only the intended tester was added to the
`securewave` group and `/etc/securewave/helper-users` allowlist. Log out and in
if group membership was newly added.

## 3. Use one stable staging account

Launch with an explicit authorized staging API using the release-provided
launcher/environment procedure. The URL must be HTTPS and must not be a
production URL. If no tester account exists, create exactly one normal staging
account manually through the app. Do not use scripts to register it. Store its
credentials in the approved password manager, then reuse that account for every
remaining step.

1. Log in and confirm servers load.
2. Record the displayed device count; it must be one after profile allocation.
3. Log out and back into the same account. Confirm the device count remains one.
4. Close and restart the app. Confirm the valid session and same account restore.
5. Confirm server loading still succeeds.

## 4. Prove WireGuard, usage, disconnect, and reconnect

Connect WireGuard in the app. Do not copy the raw profile or run `wg show`
without field selection because it exposes peer public metadata.

```bash
test -d /sys/class/net/sw-wg
sudo wg show sw-wg latest-handshakes | awk '{print "latest_handshake_epoch=" $2}'
ip route show table 51820 | wc -l
ip rule show | awk '$0 ~ /lookup 51820/ {count++} END {print count+0}'
resolvectl dns sw-wg | awk '{print "dns_server_count=" (NF > 2 ? NF-2 : 0)}'
sudo wg show sw-wg transfer | awk '{rx+=$2; tx+=$3} END {print "rx_bytes=" rx, "tx_bytes=" tx}'
```

Using a browser, load an HTTPS page and confirm normal browsing. Compare the
pre-connect and connected exit IP locally, but record only `changed=true/false`,
never either address. Confirm a recent nonzero handshake, full-tunnel route and
policy evidence, protected DNS, positive counters, and an increasing usage gauge
after traffic.

Disconnect in the app, then verify cleanup:

```bash
test ! -d /sys/class/net/sw-wg
test "$(ip route show table 51820 2>/dev/null | wc -l)" -eq 0
test "$(ip rule show | awk '$0 ~ /lookup 51820/ {count++} END {print count+0}')" -eq 0
sudo nft list ruleset 2>/dev/null | grep -q securewave && echo 'FAIL: SecureWave nft residue' || true
```

Confirm browsing uses the original route/DNS again. Reconnect once, repeat the
handshake, HTTPS, exit-change, counter, and usage checks, then disconnect and
repeat cleanup. The same account and same single device must still be present.

## 5. Collect redacted feedback and uninstall

While connected and once again after final disconnect, run:

```bash
bash scripts/collect_linux_tester_diagnostics.sh \
  --package "$PACKAGE" --checksum "$EXPECTED_SHA256" \
  --output securewave-feedback
```

Inspect the archive before sending it. It contains allowlisted summaries only;
it must not contain credentials, tokens, keys, profiles, full public addresses,
environment dumps, journals, or unrelated files.

Finally uninstall and prove residue is absent:

```bash
sudo apt purge securewave-vpn
test ! -e /usr/local/libexec/securewave-helperd
test ! -e /usr/local/libexec/securewave-wg-quick
test ! -e /usr/local/libexec/securewave-wg-quick.contract
test ! -e /run/securewave/helper.sock
test ! -d /sys/class/net/sw-wg
test "$(ip route show table 51820 2>/dev/null | wc -l)" -eq 0
test "$(ip rule show | awk '$0 ~ /lookup 51820/ {count++} END {print count+0}')" -eq 0
```

Report pass/fail for install, account/device reuse, restart restoration, server
loading, connect, handshake, routes, DNS, HTTPS, exit change, counters, usage,
disconnect cleanup, reconnect, purge, and residue. Attach only the inspected
redacted bundle.
