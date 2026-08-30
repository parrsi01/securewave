#!/usr/bin/env bash
set -euo pipefail

# Deploy one exact Git revision through SecureWave's existing native
# systemd + Gunicorn release-directory architecture.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

required=(
  SECUREWAVE_PRODUCTION_HOST
  SECUREWAVE_PRODUCTION_SSH_KEY_FILE
  SECUREWAVE_PRODUCTION_KNOWN_HOSTS_FILE
  SECUREWAVE_RELEASE_SHA
  SECUREWAVE_RELEASE_VERSION
)
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required environment variable: $name" >&2
    exit 2
  fi
done

if [[ ! "$SECUREWAVE_RELEASE_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "SECUREWAVE_RELEASE_SHA must be a full lowercase Git SHA." >&2
  exit 2
fi
if [[ ! "$SECUREWAVE_RELEASE_VERSION" =~ ^[0-9A-Za-z.+_-]+$ ]]; then
  echo "SECUREWAVE_RELEASE_VERSION contains unsupported characters." >&2
  exit 2
fi
for file in "$SECUREWAVE_PRODUCTION_SSH_KEY_FILE" "$SECUREWAVE_PRODUCTION_KNOWN_HOSTS_FILE"; do
  if [[ ! -s "$file" ]]; then
    echo "Required SSH input is missing or empty: $file" >&2
    exit 2
  fi
done
case "$SECUREWAVE_PRODUCTION_HOST" in
  localhost|localhost.*|127.*|::1|0.0.0.0|http://*|https://*|*/*|*" "*)
    echo "SECUREWAVE_PRODUCTION_HOST is not a valid production host identifier." >&2
    exit 2
    ;;
esac

actual_sha="$(git -C "$ROOT_DIR" rev-parse HEAD)"
if [[ "$actual_sha" != "$SECUREWAVE_RELEASE_SHA" ]]; then
  echo "Checkout SHA mismatch: expected $SECUREWAVE_RELEASE_SHA, found $actual_sha" >&2
  exit 2
fi
if [[ -n "$(git -C "$ROOT_DIR" status --short --untracked-files=no)" ]]; then
  echo "Tracked checkout changes detected; refusing deployment." >&2
  exit 2
fi

remote_user="${SECUREWAVE_PRODUCTION_USER:-securewave}"
release_root="${SECUREWAVE_PRODUCTION_RELEASE_ROOT:-/opt/securewave-beta}"
service="${SECUREWAVE_PRODUCTION_SERVICE:-securewave-api.service}"
local_url="${SECUREWAVE_PRODUCTION_LOCAL_URL:-http://127.0.0.1:8000}"
public_url="${SECUREWAVE_PUBLIC_BASE_URL:-https://api.securewaveapp.com}"
remote="${remote_user}@${SECUREWAVE_PRODUCTION_HOST}"

ssh_opts=(
  -o BatchMode=yes
  -o IdentitiesOnly=yes
  -o StrictHostKeyChecking=yes
  -o "UserKnownHostsFile=$SECUREWAVE_PRODUCTION_KNOWN_HOSTS_FILE"
  -i "$SECUREWAVE_PRODUCTION_SSH_KEY_FILE"
)

archive="$(mktemp --suffix=.tar.gz)"
trap 'rm -f "$archive"' EXIT
git -C "$ROOT_DIR" archive --format=tar.gz --output="$archive" "$SECUREWAVE_RELEASE_SHA"

remote_archive="/tmp/securewave-${SECUREWAVE_RELEASE_SHA}.tar.gz"
scp "${ssh_opts[@]}" "$archive" "$remote:$remote_archive"

ssh "${ssh_opts[@]}" "$remote" bash -s -- \
  "$release_root" "$service" "$SECUREWAVE_RELEASE_SHA" \
  "$SECUREWAVE_RELEASE_VERSION" "$remote_archive" "$local_url" <<'REMOTE'
set -euo pipefail

release_root="$1"
service="$2"
release_sha="$3"
release_version="$4"
archive="$5"
local_url="$6"
releases="$release_root/releases"
shared="$release_root/shared"
current="$release_root/current"
release="$releases/$release_sha"
previous=""
activated=0

rollback() {
  status=$?
  if [[ "$activated" -eq 1 && -n "$previous" && -d "$previous" ]]; then
    sudo ln -sfn "$previous" "$current"
    sudo systemctl restart "$service" || true
    echo "Deployment failed; previous release restored." >&2
  fi
  sudo rm -f "$archive"
  exit "$status"
}
trap rollback ERR

sudo -n true
sudo systemctl cat "$service" >/dev/null
sudo test -s "$shared/.env"
if [[ -L "$current" ]]; then
  previous="$(readlink -f "$current")"
fi
if [[ -z "$previous" || ! -d "$previous" ]]; then
  echo "Existing native current-release pointer is missing: $current" >&2
  exit 2
fi
if ! sudo systemctl cat "$service" | grep -Fq "$current"; then
  echo "Service does not use the existing current-release pointer: $current" >&2
  exit 2
fi

sudo install -d -o "$USER" -g "$USER" "$releases"
if [[ -e "$release" ]]; then
  echo "Target release already exists: $release" >&2
  exit 2
fi
install -d "$release"
tar -xzf "$archive" -C "$release"
rm -f "$archive"
printf '{"version":"%s","commit":"%s"}\n' "$release_version" "$release_sha" > "$release/.release.json"
ln -s "$shared/.env" "$release/.env"

# Preserve already-published immutable download bytes. Manifest metadata comes
# from the new release; artifacts remain unchanged unless published separately.
if [[ -d "$previous/static/downloads" ]]; then
  find "$previous/static/downloads" -maxdepth 1 -type f ! -name manifest.json -exec cp -p {} "$release/static/downloads/" \;
fi

python3 -m venv "$release/.venv"
"$release/.venv/bin/pip" install --disable-pip-version-check -r "$release/requirements_production.txt"
set -a
# shellcheck disable=SC1090
source "$shared/.env"
set +a
cd "$release"
"$release/.venv/bin/python" -c 'import main; print("release import passed")'
"$release/.venv/bin/python" -m alembic upgrade head

# Fail before activation if an advertised available download is absent or its
# checksum does not match. The route intentionally downgrades such rows.
"$release/.venv/bin/python" - <<'PY'
import json
from pathlib import Path
from routes.downloads import DOWNLOAD_MANIFEST_PATH, _build_download_entries

manifest = json.loads(Path(DOWNLOAD_MANIFEST_PATH).read_text(encoding="utf-8"))
expected = {
    row["filename"]
    for row in manifest["downloads"]
    if row.get("status") == "available"
}
actual = {
    row.filename
    for row in _build_download_entries()
    if row.status == "available"
}
missing = sorted(expected - actual)
if missing:
    raise SystemExit(f"Published download validation failed: {missing}")
print("published download validation passed")
PY

sudo ln -sfn "$release" "$current"
activated=1
sudo systemctl restart "$service"
sudo systemctl is-active --quiet "$service"

for path in /api/health /api/ready /api/downloads /version; do
  curl --fail --silent --show-error --retry 12 --retry-delay 2 "$local_url$path" >/dev/null
done
observed="$(curl --fail --silent --show-error "$local_url/version")"
python3 - "$release_version" "$release_sha" "$observed" <<'PY'
import json
import sys

expected_version, expected_sha, payload = sys.argv[1:]
data = json.loads(payload)
if data.get("version") != expected_version or data.get("commit") != expected_sha:
    raise SystemExit(f"Release identity mismatch: {data}")
PY

activated=0
trap - ERR
echo "Native production activation passed: $release_sha"
REMOTE

for path in /api/health /api/ready /api/downloads /version; do
  curl --fail --silent --show-error --retry 12 --retry-delay 2 "$public_url$path" >/dev/null
done
public_identity="$(curl --fail --silent --show-error "$public_url/version")"
python3 - "$SECUREWAVE_RELEASE_VERSION" "$SECUREWAVE_RELEASE_SHA" "$public_identity" <<'PY'
import json
import sys

expected_version, expected_sha, payload = sys.argv[1:]
data = json.loads(payload)
if data.get("version") != expected_version or data.get("commit") != expected_sha:
    raise SystemExit(f"Public release identity mismatch: {data}")
print("Public production verification passed")
PY
