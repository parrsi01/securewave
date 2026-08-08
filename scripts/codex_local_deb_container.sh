#!/usr/bin/env bash
set -euo pipefail

mode="${1:-build}"
case "$mode" in
  build)
    test -d /source
    test -d /out
    cd /
    rm -rf /work
    mkdir -p /work
    source_sha="$(git -C /source rev-parse HEAD)"
    source_tree="$(git -C /source rev-parse "$source_sha^{tree}")"
    # Copy objects without hardlinks or writes to the read-only source mount,
    # then check out the exact reviewed commit in the container workspace.
    git clone --quiet --no-hardlinks --no-checkout /source /work
    git -C /work checkout --quiet --detach "$source_sha"
    test "$(git -C /work rev-parse HEAD)" = "$source_sha"
    test "$(git -C /work rev-parse "HEAD^{tree}")" = "$source_tree"
    test -z "$(git -C /work status --porcelain --untracked-files=all)"

    cd /work
    exec bash scripts/build_codex_local_deb.sh \
      --api-base "${SECUREWAVE_API_BASE_URL:?SECUREWAVE_API_BASE_URL is required}" \
      --output-dir /out
    ;;
  validate)
    packages=(/out/securewave-vpn-codex-local_*.deb)
    test "${#packages[@]}" -eq 1
    package="${packages[0]}"

    printf 'package_filename=%s\n' "$(basename "$package")"
    printf 'package=%s\n' "$(dpkg-deb --field "$package" Package)"
    printf 'version=%s\n' "$(dpkg-deb --field "$package" Version)"
    printf 'architecture=%s\n' "$(dpkg-deb --field "$package" Architecture)"
    printf 'depends=%s\n' "$(dpkg-deb --field "$package" Depends)"
    printf 'contents_begin\n'
    dpkg-deb --contents "$package"
    printf 'contents_end\n'

    extract_root="$(mktemp -d)"
    trap 'rm -rf "$extract_root"' EXIT
    dpkg-deb --extract "$package" "$extract_root" >/dev/null
    release_root="$extract_root/usr/share/securewave/release"
    for field in \
      source-sha \
      source-tree-state \
      app-version \
      package-architecture \
      package-profile \
      api-base-fingerprint \
      helper-contract; do
      test -f "$release_root/$field"
      value="$(tr '\n' ' ' < "$release_root/$field" | sed 's/[[:space:]]\+$//')"
      printf 'provenance_%s=%s\n' "$field" "$value"
    done
    ;;
  *)
    echo "unsupported fixed local package mode" >&2
    exit 64
    ;;
esac
