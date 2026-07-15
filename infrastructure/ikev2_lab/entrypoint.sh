#!/usr/bin/env bash
# Start an isolated charon-systemd + swanctl instance inside one lab container.
set -euo pipefail

if [[ "${SECUREWAVE_LAB_SKIP_CHARON:-0}" == "1" ]]; then
  exec "$@"
fi

charon="$(command -v charon-systemd || true)"
[[ -n "$charon" && -x "$charon" ]] || {
  echo "charon-systemd is unavailable" >&2
  exit 1
}

mkdir -p /var/run
"$charon" --debug-ike 1 --debug-knl 1 &
charon_pid=$!

stop() {
  kill "$charon_pid" 2>/dev/null || true
  wait "$charon_pid" 2>/dev/null || true
}
trap stop EXIT INT TERM

for _ in $(seq 1 100); do
  [[ -S /var/run/charon.vici ]] && break
  kill -0 "$charon_pid" 2>/dev/null || {
    echo "charon-systemd exited before its VICI socket was ready" >&2
    exit 1
  }
  sleep 0.1
done
[[ -S /var/run/charon.vici ]] || { echo "VICI socket was not created" >&2; exit 1; }

swanctl --load-all --clear --noprompt

"$@" &
main_pid=$!
wait "$main_pid"
