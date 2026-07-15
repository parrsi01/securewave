#!/usr/bin/env bash
# Disposable, local-only strongSwan IKEv2 data-plane lab.
#
# It creates two Docker bridge networks with no external routing: a client and
# gateway share the transport network; the gateway alone joins a second private
# egress/DNS network. No Hetzner API, SecureWave API, production address, or
# credential is used. All generated CA, certificate, and EAP material lives in
# a mode-0700 temporary directory and is removed on exit.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAB_DIR=""
# Docker installed through Snap cannot reliably bind-mount the host /tmp on
# this Ubuntu image. Keep short-lived secret lab material in a private user
# cache directory instead; it is removed by the EXIT trap.
LAB_PARENT="${XDG_CACHE_HOME:-$HOME/.cache}/securewave-ikev2-lab"
RUN_ID="$(date +%s)-$$"
TAG="securewave-ikev2-lab:local"
LABEL="securewave.lab=ikev2"
TRANSPORT="securewave-ikev2-lab-${RUN_ID}-transport"
EGRESS_NET="securewave-ikev2-lab-${RUN_ID}-egress"
GATEWAY="securewave-ikev2-lab-${RUN_ID}-gateway"
CLIENT="securewave-ikev2-lab-${RUN_ID}-client"
BAD_CLIENT="securewave-ikev2-lab-${RUN_ID}-bad-client"
EGRESS="securewave-ikev2-lab-${RUN_ID}-egress"

usage() {
  cat <<'EOF'
Usage: scripts/ikev2_container_lab.sh --preflight|--run

--preflight verifies only local Docker and source prerequisites.
--run builds a local Ubuntu lab image, runs a disposable IKEv2 EAP-MSCHAPv2
gateway/client/egress topology, and checks handshake, XFRM/ESP, endpoint
bypass, private DNS, HTTPS/egress movement, counters, rekey, failed auth,
network transition/reconnect, disconnect, and container cleanup.
EOF
}

fail() {
  echo "IKEv2 lab: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command is unavailable: $1"
}

preflight() {
  require_command docker
  require_command openssl
  require_command pki
  docker info >/dev/null 2>&1 || fail "Docker daemon is not available to this user"
  if docker ps -aq --filter label=securewave.lab=ikev2 | grep -q .; then
    fail "a previous SecureWave IKEv2 lab container remains; remove that exact labeled container before starting another lab"
  fi
  [[ -f "$ROOT/infrastructure/ikev2_lab/Dockerfile" ]] || fail "lab image source is missing"
  [[ -x "$ROOT/infrastructure/ikev2_lab/entrypoint.sh" ]] || fail "lab entrypoint is not executable"
  [[ -x "$ROOT/scripts/ikev2_container_lab.sh" ]] || fail "lab runner is not executable"
  echo "IKEv2 lab preflight passed: local Docker only; no external staging target is configured."
}

cleanup() {
  local failed=0
  set +e
  for container in "$BAD_CLIENT" "$CLIENT" "$GATEWAY" "$EGRESS"; do
    if [[ "$(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null || true)" == "true" ]]; then
      # Some confined Docker installations cannot signal a container from the
      # daemon. Ask the lab-owned PID 1 to run its trap and exit first.
      docker exec "$container" kill -TERM 1 >/dev/null 2>&1 || true
      for _ in $(seq 1 20); do
        [[ "$(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null || true)" != "true" ]] && break
        sleep 0.1
      done
    fi
    docker rm -f "$container" >/dev/null 2>&1 || {
      if docker ps -a --format '{{.Names}}' | grep -Fxq "$container"; then
        echo "IKEv2 lab cleanup could not remove $container" >&2
        failed=1
      fi
    }
  done
  docker network rm "$TRANSPORT" "$EGRESS_NET" >/dev/null 2>&1 || true
  [[ -z "$LAB_DIR" ]] || rm -rf "$LAB_DIR"
  return "$failed"
}

on_exit() {
  local original=$?
  trap - EXIT
  if ! cleanup && [[ "$original" == "0" ]]; then
    exit 1
  fi
  exit "$original"
}

wait_for() {
  local container="$1"
  local check="$2"
  for _ in $(seq 1 60); do
    if docker exec "$container" bash -ec "$check" >/dev/null 2>&1; then
      return 0
    fi
    if [[ "$(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null || true)" != "true" ]]; then
      docker logs "$container" >&2 || true
      fail "$container exited before becoming ready"
    fi
    sleep 1
  done
  docker logs "$container" >&2 || true
  fail "$container did not become ready"
}

make_swanctl_tree() {
  local role="$1"
  local tree="$2"
  install -d -m 0700 "$tree/private" "$tree/x509" "$tree/x509ca" "$tree/conf.d"
  printf 'include conf.d/*.conf\n' >"$tree/swanctl.conf"
  install -m 0600 "$LAB_DIR/pki/ca.pem" "$tree/x509ca/ca.pem"
  if [[ "$role" == gateway ]]; then
    install -m 0600 "$LAB_DIR/pki/gateway-key.pem" "$tree/private/gateway-key.pem"
    install -m 0644 "$LAB_DIR/pki/gateway-cert.pem" "$tree/x509/gateway-cert.pem"
  fi
}

write_configurations() {
  local username eap_token
  username="swikev2-$(openssl rand -hex 16)"
  eap_token="$(openssl rand -base64 48 | tr -d '=+/\n' | cut -c1-40)"
  [[ "$username" =~ ^swikev2-[a-f0-9]{32}$ ]] || fail "generated lab username was invalid"
  [[ "$eap_token" =~ ^[A-Za-z0-9_-]{32,128}$ ]] || fail "generated lab secret was invalid"

  make_swanctl_tree gateway "$LAB_DIR/gateway/swanctl"
  make_swanctl_tree client "$LAB_DIR/client/swanctl"
  make_swanctl_tree client "$LAB_DIR/bad-client/swanctl"

  cat >"$LAB_DIR/gateway/swanctl/conf.d/securewave-lab.conf" <<EOF
connections {
  securewave-lab {
    version = 2
    local_addrs = 172.29.0.2
    proposals = aes256gcm16-prfsha256-ecp256
    rekey_time = 2m
    dpd_delay = 5s
    dpd_timeout = 20s
    unique = replace
    pools = securewave-lab-ipv4
    local {
      auth = pubkey
      certs = gateway-cert.pem
      id = gateway.ikev2.lab
    }
    remote {
      auth = eap-mschapv2
      eap_id = %any
    }
    children {
      securewave-lab-net {
        local_ts = 0.0.0.0/0
        rekey_time = 1m
        dpd_action = clear
        start_action = none
      }
    }
  }
}
pools {
  securewave-lab-ipv4 {
    addrs = 10.77.0.0/24
    dns = 172.30.0.3
  }
}
secrets {
  eap-lab {
    id = "$username"
    secret = $eap_token
  }
}
EOF

  cat >"$LAB_DIR/client/swanctl/conf.d/securewave-lab.conf" <<EOF
connections {
  securewave-lab {
    version = 2
    remote_addrs = 172.29.0.2
    vips = 0.0.0.0
    proposals = aes256gcm16-prfsha256-ecp256
    local {
      auth = eap-mschapv2
      eap_id = "$username"
    }
    remote {
      auth = pubkey
      id = gateway.ikev2.lab
      cacerts = ca.pem
    }
    children {
      securewave-lab-net {
        local_ts = dynamic
        remote_ts = 0.0.0.0/0
        start_action = none
      }
    }
  }
}
secrets {
  eap-lab {
    id = "$username"
    secret = $eap_token
  }
}
EOF
  sed 's/secret = [^[:space:]]*/secret = invalid-lab-secret-not-accepted/' \
    "$LAB_DIR/client/swanctl/conf.d/securewave-lab.conf" \
    >"$LAB_DIR/bad-client/swanctl/conf.d/securewave-lab.conf"
  chmod 0600 "$LAB_DIR"/*/swanctl/conf.d/securewave-lab.conf
}

generate_material() {
  install -d -m 0700 "$LAB_DIR/pki" "$LAB_DIR/egress"
  umask 077
  pki --gen --type ed25519 --outform pem >"$LAB_DIR/pki/ca-key.pem"
  pki --self --ca --lifetime 1 --in "$LAB_DIR/pki/ca-key.pem" --type ed25519 \
    --dn 'CN=SecureWave IKEv2 Lab CA' --outform pem >"$LAB_DIR/pki/ca.pem"
  pki --gen --type ed25519 --outform pem >"$LAB_DIR/pki/gateway-key.pem"
  pki --pub --in "$LAB_DIR/pki/gateway-key.pem" | \
    pki --issue --lifetime 1 --cacert "$LAB_DIR/pki/ca.pem" --cakey "$LAB_DIR/pki/ca-key.pem" \
      --dn 'CN=gateway.ikev2.lab' --san gateway.ikev2.lab --san 172.29.0.2 \
      --flag serverAuth --outform pem \
      >"$LAB_DIR/pki/gateway-cert.pem"
  openssl req -x509 -newkey ed25519 -nodes -days 1 \
    -subj '/CN=egress.ikev2.lab' \
    -keyout "$LAB_DIR/egress/key.pem" -out "$LAB_DIR/egress/cert.pem" >/dev/null 2>&1
  write_configurations
}

run_lab() {
  preflight
  install -d -m 0700 "$LAB_PARENT"
  LAB_DIR="$(mktemp -d "$LAB_PARENT/run.XXXXXX")"
  chmod 0700 "$LAB_DIR"
  trap on_exit EXIT
  generate_material

  docker build --pull=false --tag "$TAG" "$ROOT/infrastructure/ikev2_lab" >/dev/null
  docker network create --internal --subnet 172.29.0.0/24 --label "$LABEL" "$TRANSPORT" >/dev/null
  docker network create --internal --subnet 172.30.0.0/24 --label "$LABEL" "$EGRESS_NET" >/dev/null

  docker run -d --name "$GATEWAY" --label "$LABEL" --cap-add NET_ADMIN --cap-add NET_RAW \
    --sysctl net.ipv4.ip_forward=1 --network "$TRANSPORT" --ip 172.29.0.2 \
    -v "$LAB_DIR/gateway/swanctl:/etc/swanctl:ro" "$TAG" \
    timeout --signal=KILL 180 sleep infinity >/dev/null
  docker network connect --ip 172.30.0.2 "$EGRESS_NET" "$GATEWAY"
  wait_for "$GATEWAY" 'swanctl --list-conns | grep -q "securewave-lab"'
  docker exec "$GATEWAY" bash -ec '
    egress_if=""
    for candidate in /sys/class/net/*; do
      candidate="${candidate##*/}"
      if ip -o -4 addr show dev "$candidate" | grep -Fq "172.30.0.2/24"; then
        egress_if="$candidate"
        break
      fi
    done
    [[ -n "$egress_if" ]]
    iptables -A FORWARD -s 10.77.0.0/24 -o "$egress_if" -j ACCEPT
    iptables -A FORWARD -d 10.77.0.0/24 -i "$egress_if" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -t nat -A POSTROUTING -s 10.77.0.0/24 -o "$egress_if" -j MASQUERADE
  '

  # Start this only after the gateway is healthy.  Every lab container has a
  # bounded lifetime so a Docker/AppArmor stop failure cannot leave a permanent
  # background workload on the development host.
  docker run -d --name "$EGRESS" --label "$LABEL" --network "$EGRESS_NET" --ip 172.30.0.3 \
    --env SECUREWAVE_LAB_SKIP_CHARON=1 -v "$LAB_DIR/egress:/lab:ro" "$TAG" \
    bash -ec 'dnsmasq --keep-in-foreground --no-resolv --address=/egress.ikev2.lab/172.30.0.3 & exec timeout --signal=KILL 180 /usr/local/libexec/securewave-ikev2-lab-egress --cert /lab/cert.pem --key /lab/key.pem' \
    >/dev/null
  wait_for "$EGRESS" 'ss -H -lnt | grep -q ":8443" && ss -H -lun | grep -q ":53"'

  docker run -d --name "$CLIENT" --label "$LABEL" --cap-add NET_ADMIN --cap-add NET_RAW \
    --network "$TRANSPORT" --ip 172.29.0.3 \
    -v "$LAB_DIR/client/swanctl:/etc/swanctl:ro" "$TAG" \
    timeout --signal=KILL 180 sleep infinity >/dev/null
  wait_for "$CLIENT" 'swanctl --list-conns | grep -q "securewave-lab"'
  if docker exec "$CLIENT" curl --max-time 3 --silent --show-error --insecure https://172.30.0.3:8443/ >/dev/null 2>&1; then
    fail "private egress service was reachable before the IKEv2 tunnel"
  fi
  docker exec "$CLIENT" bash -ec 'ip route get 172.29.0.2 | grep -q "dev eth0"'
  docker exec "$CLIENT" swanctl --initiate --child securewave-lab-net >/dev/null
  wait_for "$CLIENT" 'swanctl --list-sas | grep -q "ESTABLISHED"'
  docker exec "$CLIENT" bash -ec 'ip xfrm state | grep -q "proto esp" && ip xfrm policy | grep -q "dir out"'

  response="$(docker exec "$CLIENT" curl --max-time 10 --silent --show-error --insecure https://172.30.0.3:8443/)"
  observed_source="$(python3 -c 'import json, sys; print(json.load(sys.stdin)["source"])' <<<"$response")"
  [[ "$observed_source" == "172.30.0.2" ]] || fail "HTTPS egress source did not move through the gateway"
  docker exec "$CLIENT" bash -ec 'dig +short @172.30.0.3 egress.ikev2.lab | grep -Fxq 172.30.0.3'
  docker exec "$CLIENT" bash -ec 'ip -s xfrm state | grep -q "bytes"'

  docker exec "$CLIENT" swanctl --rekey --ike securewave-lab >/dev/null
  wait_for "$CLIENT" 'swanctl --list-sas | grep -q "ESTABLISHED"'

  docker run -d --name "$BAD_CLIENT" --label "$LABEL" --cap-add NET_ADMIN --cap-add NET_RAW \
    --network "$TRANSPORT" --ip 172.29.0.4 \
    -v "$LAB_DIR/bad-client/swanctl:/etc/swanctl:ro" "$TAG" \
    timeout --signal=KILL 180 sleep infinity >/dev/null
  wait_for "$BAD_CLIENT" 'swanctl --list-conns | grep -q "securewave-lab"'
  if docker exec "$BAD_CLIENT" swanctl --initiate --child securewave-lab-net >/dev/null 2>&1; then
    fail "invalid EAP credential unexpectedly established an IKEv2 tunnel"
  fi
  if docker exec "$BAD_CLIENT" swanctl --list-sas | grep -q "ESTABLISHED"; then
    fail "invalid EAP credential left an established IKEv2 SA"
  fi

  docker exec "$CLIENT" swanctl --terminate --ike securewave-lab >/dev/null
  docker network disconnect "$TRANSPORT" "$CLIENT"
  docker network connect --ip 172.29.0.3 "$TRANSPORT" "$CLIENT"
  docker exec "$CLIENT" swanctl --initiate --child securewave-lab-net >/dev/null
  wait_for "$CLIENT" 'swanctl --list-sas | grep -q "ESTABLISHED"'
  docker exec "$CLIENT" swanctl --terminate --ike securewave-lab >/dev/null
  if docker exec "$CLIENT" swanctl --list-sas | grep -q "ESTABLISHED"; then
    fail "disconnect left an established IKEv2 SA"
  fi
  if docker exec "$CLIENT" ip xfrm state | grep -q "proto esp"; then
    fail "disconnect left ESP XFRM state"
  fi

  echo "IKEv2 local lab passed: EAP, ESP/XFRM, endpoint bypass, private DNS/HTTPS egress, rekey, failed auth, reconnect, disconnect, and cleanup were exercised."
}

case "${1:-}" in
  --preflight) preflight ;;
  --run) run_lab ;;
  --help|-h|'') usage ;;
  *) usage; exit 64 ;;
esac
