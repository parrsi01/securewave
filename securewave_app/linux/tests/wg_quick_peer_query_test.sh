#!/usr/bin/env bash
set -euo pipefail

helper_script="$1"
tmpdir="$(mktemp -d)"
trap 'rm -rf -- "$tmpdir"' EXIT

cat > "$tmpdir/wg" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "$SECUREWAVE_TEST_WG_CALL"
test_key="$(printf '%43s' '' | tr ' ' 'A')="
printf '%s 1234567890\n' "$test_key"
MOCK
chmod 0755 "$tmpdir/wg"

export PATH="$tmpdir:$PATH"
export SECUREWAVE_TEST_WG_CALL="$tmpdir/wg-call"
"$helper_script" wireguard-peer-handshakes > "$tmpdir/output"
printf 'show\nsw-wg\nlatest-handshakes\n' > "$tmpdir/expected-call"
diff -u "$tmpdir/expected-call" "$tmpdir/wg-call"
test_key="$(printf '%43s' '' | tr ' ' 'A')="
grep -Fqx "$test_key 1234567890" "$tmpdir/output"

rm -f "$tmpdir/wg-call"
if "$helper_script" wireguard-peer-handshakes eth0 >/dev/null 2>&1; then
  echo "helper accepted a caller-selected interface" >&2
  exit 1
fi
test ! -e "$tmpdir/wg-call"
