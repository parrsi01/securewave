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
    # Docker Desktop on macOS can fail while Git packs objects from a
    # read-only bind mount. Archive the exact commit, then reconstruct only
    # its tree and commit object in the temporary container repository.
    git -C /source archive --format=tar "$source_sha" | tar -xf - -C /work
    cd /work
    git init --quiet
    git config user.email codex-local@invalid.example
    git config user.name SecureWave-Codex-Local
    git add --all
    test "$(git write-tree)" = "$source_tree"
    written_sha="$(git -C /source cat-file commit "$source_sha" | git hash-object -w -t commit --stdin)"
    test "$written_sha" = "$source_sha"
    git update-ref refs/heads/codex-local "$source_sha"
    git symbolic-ref HEAD refs/heads/codex-local
    git -C /work checkout --detach HEAD >/dev/null
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
