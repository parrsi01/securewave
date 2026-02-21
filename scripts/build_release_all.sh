#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_DIR="${ROOT_DIR}/securewave_app"
DOWNLOADS_DIR="${ROOT_DIR}/static/downloads"
INPUT_DIR="${SECUREWAVE_RELEASE_INPUT_DIR:-${ROOT_DIR}/artifacts/release_inputs}"

VERSION="${1:-}"
if [[ -z "${VERSION}" ]]; then
  if [[ -f "${ROOT_DIR}/VERSION" ]]; then
    VERSION="$(tr -d '\r\n' < "${ROOT_DIR}/VERSION" | xargs)"
  fi
fi
if [[ -z "${VERSION}" ]]; then
  echo "ERROR: release version is required (arg or VERSION file)." >&2
  exit 1
fi

VERSION_TAG="${VERSION//+/-}"
BUILD_DATE="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
GENERATED_AT="${BUILD_DATE}"

RELEASE_DIR="${ROOT_DIR}/artifacts/releases/${VERSION}"
ENTRY_FILE="${RELEASE_DIR}/manifest_entries.tsv"
CHECKSUM_FILE="${RELEASE_DIR}/checksums.txt"
MANIFEST_FILE="${RELEASE_DIR}/version.json"

mkdir -p "${RELEASE_DIR}" "${DOWNLOADS_DIR}" "${INPUT_DIR}"
# Ensure each run produces a clean per-version release directory.
find "${RELEASE_DIR}" -mindepth 1 -maxdepth 1 -type f -delete

: > "${ENTRY_FILE}"
: > "${CHECKSUM_FILE}"
printf 'platform\tarchitecture\tformat\tfilename\tstatus\tprimary\tsigned\turl\tnotes\tsigning_notes\tsha256\tsize_bytes\n' >> "${ENTRY_FILE}"

clean_field() {
  echo "${1:-}" | tr '\t\r\n' '   '
}

append_entry() {
  local platform="$1"
  local architecture="$2"
  local format="$3"
  local filename="$4"
  local status="$5"
  local primary="$6"
  local signed="$7"
  local url="$8"
  local notes="$9"
  local signing_notes="${10}"
  local sha256="${11}"
  local size_bytes="${12}"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(clean_field "${platform}")" \
    "$(clean_field "${architecture}")" \
    "$(clean_field "${format}")" \
    "$(clean_field "${filename}")" \
    "$(clean_field "${status}")" \
    "$(clean_field "${primary}")" \
    "$(clean_field "${signed}")" \
    "$(clean_field "${url}")" \
    "$(clean_field "${notes}")" \
    "$(clean_field "${signing_notes}")" \
    "$(clean_field "${sha256}")" \
    "$(clean_field "${size_bytes}")" \
    >> "${ENTRY_FILE}"
}

publish_local_artifact() {
  local platform="$1"
  local architecture="$2"
  local format="$3"
  local source_path="$4"
  local target_name="$5"
  local primary="$6"
  local signed="$7"
  local notes="$8"
  local signing_notes="$9"

  local release_path="${RELEASE_DIR}/${target_name}"
  cp -f "${source_path}" "${release_path}"

  local sha256
  sha256="$(sha256sum "${release_path}" | awk '{print $1}')"
  local size_bytes
  size_bytes="$(wc -c < "${release_path}" | tr -d ' ')"

  printf '%s  %s\n' "${sha256}" "${target_name}" >> "${CHECKSUM_FILE}"

  append_entry \
    "${platform}" \
    "${architecture}" \
    "${format}" \
    "${target_name}" \
    "available" \
    "${primary}" \
    "${signed}" \
    "/downloads/${target_name}" \
    "${notes}" \
    "${signing_notes}" \
    "${sha256}" \
    "${size_bytes}"
}

maybe_publish_optional_artifact() {
  local platform="$1"
  local architecture="$2"
  local format="$3"
  local source_path="$4"
  local target_name="$5"
  local primary="$6"
  local signed="$7"
  local available_note="$8"
  local unavailable_note="$9"
  local signing_notes="${10}"

  if [[ -f "${source_path}" ]]; then
    publish_local_artifact \
      "${platform}" \
      "${architecture}" \
      "${format}" \
      "${source_path}" \
      "${target_name}" \
      "${primary}" \
      "${signed}" \
      "${available_note}" \
      "${signing_notes}"
  else
    append_entry \
      "${platform}" \
      "${architecture}" \
      "${format}" \
      "" \
      "unavailable" \
      "${primary}" \
      "${signed}" \
      "" \
      "${unavailable_note}" \
      "${signing_notes}" \
      "" \
      ""
  fi
}

echo "==> SecureWave release build"
echo "    Version: ${VERSION}"
echo "    Build date (UTC): ${BUILD_DATE}"
echo "    Input dir: ${INPUT_DIR}"

echo "==> Building Linux .deb (primary artifact)"
(
  cd "${APP_DIR}"
  ./scripts/build_deb.sh
)

deb_candidate="$(ls -1t "${APP_DIR}"/build/packaging/*.deb 2>/dev/null | head -1 || true)"
if [[ -z "${deb_candidate}" ]]; then
  echo "ERROR: Linux .deb build did not produce an artifact." >&2
  exit 2
fi

deb_arch_raw="$(dpkg-deb -f "${deb_candidate}" Architecture 2>/dev/null || true)"
case "${deb_arch_raw}" in
  amd64|x86_64)
    linux_arch="x64"
    ;;
  arm64|aarch64)
    linux_arch="arm64"
    ;;
  *)
    linux_arch="${deb_arch_raw:-x64}"
    ;;
esac

linux_target="securewave-linux-${linux_arch}-${VERSION_TAG}.deb"
publish_local_artifact \
  "linux" \
  "${linux_arch}" \
  "deb" \
  "${deb_candidate}" \
  "${linux_target}" \
  "true" \
  "false" \
  "Primary Linux package for Ubuntu/Debian systems." \
  "Unsigned .deb: distribute with SHA256 verification and signed release notes."

# Optional: Windows installer (from Windows build host/CI drop).
windows_candidate=""
for candidate in \
  "${INPUT_DIR}/securewave-windows-x64-setup.exe" \
  "${ROOT_DIR}/artifacts/windows_release/securewave-windows-x64-setup.exe"
do
  if [[ -f "${candidate}" ]]; then
    windows_candidate="${candidate}"
    break
  fi
done

if [[ -n "${windows_candidate}" ]]; then
  publish_local_artifact \
    "windows" \
    "x64" \
    "exe" \
    "${windows_candidate}" \
    "securewave-windows-x64-setup-${VERSION_TAG}.exe" \
    "true" \
    "false" \
    "Windows installer built from native Windows toolchain." \
    "Authenticode signing required before production distribution."
else
  append_entry \
    "windows" \
    "x64" \
    "exe" \
    "" \
    "unavailable" \
    "true" \
    "false" \
    "" \
    "Windows installer not published in this release run." \
    "Authenticode signing required before production distribution." \
    "" \
    ""
fi

# Optional: macOS DMG (from native macOS build host/CI drop).
macos_candidate=""
for candidate in \
  "${INPUT_DIR}/securewave-macos-universal.dmg" \
  "${INPUT_DIR}/securewave-macos-arm64.dmg"
do
  if [[ -f "${candidate}" ]]; then
    macos_candidate="${candidate}"
    break
  fi
done

if [[ -n "${macos_candidate}" ]]; then
  publish_local_artifact \
    "macos" \
    "arm64" \
    "dmg" \
    "${macos_candidate}" \
    "securewave-macos-arm64-${VERSION_TAG}.dmg" \
    "true" \
    "false" \
    "macOS DMG from native macOS build host." \
    "Apple Developer ID signing + notarization required for non-preview release."
else
  append_entry \
    "macos" \
    "arm64" \
    "dmg" \
    "" \
    "unavailable" \
    "true" \
    "false" \
    "" \
    "Preview build only: no signed/notarized DMG attached in this run." \
    "Apple Developer ID signing + notarization required for production DMG." \
    "" \
    ""
fi

# Optional: Android APK/AAB from Linux or CI drop.
if [[ "${SECUREWAVE_BUILD_ANDROID:-0}" == "1" ]]; then
  echo "==> Building Android APK (SECUREWAVE_BUILD_ANDROID=1)"
  (
    cd "${APP_DIR}"
    flutter build apk --release
  )
fi

android_apk_candidate=""
for candidate in \
  "${APP_DIR}/build/app/outputs/flutter-apk/app-release.apk" \
  "${INPUT_DIR}/securewave-android.apk"
do
  if [[ -f "${candidate}" ]]; then
    android_apk_candidate="${candidate}"
    break
  fi
done

if [[ -n "${android_apk_candidate}" ]]; then
  publish_local_artifact \
    "android" \
    "universal" \
    "apk" \
    "${android_apk_candidate}" \
    "securewave-android-${VERSION_TAG}.apk" \
    "true" \
    "false" \
    "Android APK for direct distribution channels." \
    "Sign with Play/App Signing key in CI before production rollout."
else
  append_entry \
    "android" \
    "universal" \
    "apk" \
    "" \
    "unavailable" \
    "true" \
    "false" \
    "" \
    "Android APK not published in this release run." \
    "Use Google Play App Signing for production tracks." \
    "" \
    ""
fi

android_aab_candidate=""
for candidate in \
  "${APP_DIR}/build/app/outputs/bundle/release/app-release.aab" \
  "${INPUT_DIR}/securewave-android.aab"
do
  if [[ -f "${candidate}" ]]; then
    android_aab_candidate="${candidate}"
    break
  fi
done

if [[ -n "${android_aab_candidate}" ]]; then
  publish_local_artifact \
    "android" \
    "universal" \
    "aab" \
    "${android_aab_candidate}" \
    "securewave-android-${VERSION_TAG}.aab" \
    "false" \
    "false" \
    "Android App Bundle for Google Play release tracks." \
    "Upload to Play Console internal track first."
fi

# iOS is always TestFlight/App Store distribution (no direct binary download).
append_entry \
  "ios" \
  "arm64" \
  "testflight" \
  "" \
  "unavailable" \
  "true" \
  "false" \
  "" \
  "iOS is distributed via TestFlight/App Store only; no direct artifact on website." \
  "Manual Apple signing/provisioning required for each release." \
  "" \
  ""

# Guardrail: release artifacts must never include raw key material.
if find "${RELEASE_DIR}" -maxdepth 1 -type f \( -name '*.pem' -o -name '*.key' -o -name '*.p12' -o -name '*.pfx' \) | grep -q .; then
  echo "ERROR: key/cert files detected in ${RELEASE_DIR}." >&2
  exit 3
fi
if rg -n "BEGIN [A-Z ]*PRIVATE KEY" "${RELEASE_DIR}" >/dev/null 2>&1; then
  echo "ERROR: private key block detected in ${RELEASE_DIR}." >&2
  exit 4
fi

python3 - "${ENTRY_FILE}" "${MANIFEST_FILE}" "${VERSION}" "${BUILD_DATE}" "${GENERATED_AT}" <<'PY'
import csv
import json
import sys

entry_file, manifest_file, version, build_date, generated_at = sys.argv[1:]


def as_bool(raw: str) -> bool:
    return str(raw).strip().lower() in {"1", "true", "yes"}


artifacts = []
with open(entry_file, "r", encoding="utf-8") as handle:
    reader = csv.DictReader(handle, delimiter="\t")
    for row in reader:
        filename = row.get("filename", "").strip()
        url = row.get("url", "").strip() or None
        sha = row.get("sha256", "").strip() or None
        size_raw = row.get("size_bytes", "").strip()
        size = int(size_raw) if size_raw.isdigit() else None

        artifacts.append(
            {
                "platform": row.get("platform", "unknown").strip() or "unknown",
                "architecture": row.get("architecture", "unknown").strip() or "unknown",
                "format": row.get("format", "").strip() or None,
                "filename": filename,
                "url": url,
                "status": row.get("status", "unavailable").strip() or "unavailable",
                "primary": as_bool(row.get("primary", "false")),
                "signed": as_bool(row.get("signed", "false")),
                "notes": row.get("notes", "").strip() or None,
                "signing_notes": row.get("signing_notes", "").strip() or None,
                "sha256": sha,
                "size_bytes": size,
                "version": version,
                "build_date": build_date,
            }
        )

platform_urls = {}
for artifact in artifacts:
    if artifact.get("status") != "available" or not artifact.get("url"):
        continue
    platform = artifact.get("platform")
    if platform not in platform_urls:
        platform_urls[platform] = artifact["url"]
    if artifact.get("primary"):
        platform_urls[platform] = artifact["url"]

for platform_name in ["windows", "linux", "macos", "android", "ios"]:
    platform_urls.setdefault(platform_name, None)

manifest = {
    "version": version,
    "build_date": build_date,
    "generated_at": generated_at,
    "provider": "hetzner",
    "artifacts": artifacts,
    "platform_urls": platform_urls,
}

with open(manifest_file, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2)
    handle.write("\n")
PY

# Publish current release into static/downloads and clear stale top-level files.
find "${DOWNLOADS_DIR}" -mindepth 1 -maxdepth 1 -type f -delete
rm -rf "${DOWNLOADS_DIR}/releases"
mkdir -p "${DOWNLOADS_DIR}/releases/${VERSION}"

cp -f "${MANIFEST_FILE}" "${DOWNLOADS_DIR}/version.json"
cp -f "${CHECKSUM_FILE}" "${DOWNLOADS_DIR}/checksums-${VERSION_TAG}.txt"

while IFS= read -r release_file; do
  base_name="$(basename "${release_file}")"
  case "${base_name}" in
    manifest_entries.tsv|checksums.txt|version.json)
      continue
      ;;
  esac
  cp -f "${release_file}" "${DOWNLOADS_DIR}/${base_name}"
  cp -f "${release_file}" "${DOWNLOADS_DIR}/releases/${VERSION}/${base_name}"
done < <(find "${RELEASE_DIR}" -maxdepth 1 -type f | sort)

cp -f "${MANIFEST_FILE}" "${DOWNLOADS_DIR}/releases/${VERSION}/version.json"
cp -f "${CHECKSUM_FILE}" "${DOWNLOADS_DIR}/releases/${VERSION}/checksums.txt"

echo "==> Release manifest: ${MANIFEST_FILE}"
echo "==> Published manifest: ${DOWNLOADS_DIR}/version.json"
echo "==> Published downloads:"
ls -lh "${DOWNLOADS_DIR}"
