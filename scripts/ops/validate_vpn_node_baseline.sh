#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

PYTHON_BIN="${PYTHON_BIN:-python3}"
AUDIT_SCRIPT="${ROOT_DIR}/infrastructure/hetzner/audit_vpn_fleet.py"

ONLY_RUNNING=true
NAME_PREFIX="${NAME_PREFIX:-}"
SSH_CHECKS=true
COMPARE_BACKEND_DB=true
WG_PORT="${WG_PORT:-51820}"
OPENVPN_PORT="${OPENVPN_PORT:-1194}"
SSH_USER="${WG_SSH_USER:-root}"
SSH_KEY_PATH="${WG_SSH_KEY_PATH:-}"
SSH_PORT="${WG_SSH_PORT:-22}"
SSH_TIMEOUT="${WG_SSH_TIMEOUT:-12}"
REQUIRE_OPENVPN="${REQUIRE_OPENVPN:-true}"
REQUIRE_IKEV2="${REQUIRE_IKEV2:-true}"
REQUIRE_PRIVATE_NETWORK="${REQUIRE_PRIVATE_NETWORK:-true}"
JSON_OUT="${JSON_OUT:-${ROOT_DIR}/artifacts/ops/vpn_baseline_$(date +%Y%m%d_%H%M%S).json}"

usage() {
  cat <<EOF
Usage: $0 [options]

Strict post-deploy validator for SecureWave Hetzner VPN nodes.
Runs infrastructure/hetzner/audit_vpn_fleet.py and FAILS on baseline violations.

Options:
  --json-out <path>              Write audit report JSON (default: artifacts/ops/vpn_baseline_TIMESTAMP.json)
  --name-prefix <prefix>         Restrict audited servers by name prefix
  --wg-port <port>               WireGuard UDP port (default: 51820)
  --openvpn-port <port>          OpenVPN port (default: 1194)
  --ssh-user <user>              SSH user (default: root)
  --ssh-key-path <path>          SSH private key path (required when ssh checks enabled)
  --ssh-port <port>              SSH port (default: 22)
  --ssh-timeout <seconds>        SSH timeout (default: 12)
  --require-openvpn true|false   Require OpenVPN runtime baseline (default: true)
  --require-ikev2 true|false     Require IKEv2 runtime baseline (default: true)
  --require-private-network true|false
                                 Require Hetzner private network attachment (default: true)
  --no-ssh-checks                Disable SSH checks (not recommended)
  --no-compare-backend-db        Disable backend registry comparison
  --include-stopped              Include non-running servers
  -h, --help                     Show this help

Required environment:
  HETZNER_API_TOKEN
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json-out) JSON_OUT="$2"; shift 2 ;;
    --name-prefix) NAME_PREFIX="$2"; shift 2 ;;
    --wg-port) WG_PORT="$2"; shift 2 ;;
    --openvpn-port) OPENVPN_PORT="$2"; shift 2 ;;
    --ssh-user) SSH_USER="$2"; shift 2 ;;
    --ssh-key-path) SSH_KEY_PATH="$2"; shift 2 ;;
    --ssh-port) SSH_PORT="$2"; shift 2 ;;
    --ssh-timeout) SSH_TIMEOUT="$2"; shift 2 ;;
    --require-openvpn) REQUIRE_OPENVPN="$2"; shift 2 ;;
    --require-ikev2) REQUIRE_IKEV2="$2"; shift 2 ;;
    --require-private-network) REQUIRE_PRIVATE_NETWORK="$2"; shift 2 ;;
    --no-ssh-checks) SSH_CHECKS=false; shift ;;
    --no-compare-backend-db) COMPARE_BACKEND_DB=false; shift ;;
    --include-stopped) ONLY_RUNNING=false; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ ! -f "${AUDIT_SCRIPT}" ]]; then
  echo "Missing audit script: ${AUDIT_SCRIPT}" >&2
  exit 3
fi

if [[ -z "${HETZNER_API_TOKEN:-}" ]]; then
  echo "HETZNER_API_TOKEN must be set." >&2
  exit 4
fi

if [[ "${SSH_CHECKS}" == "true" && -n "${SSH_KEY_PATH}" && ! -f "${SSH_KEY_PATH}" ]]; then
  echo "SSH key not found: ${SSH_KEY_PATH}" >&2
  exit 5
fi

mkdir -p "$(dirname "${JSON_OUT}")"

audit_args=(
  "${AUDIT_SCRIPT}"
  "--json-out" "${JSON_OUT}"
  "--wg-port" "${WG_PORT}"
  "--openvpn-port" "${OPENVPN_PORT}"
  "--ssh-user" "${SSH_USER}"
  "--ssh-port" "${SSH_PORT}"
  "--ssh-timeout" "${SSH_TIMEOUT}"
)

if [[ "${ONLY_RUNNING}" == "true" ]]; then
  audit_args+=("--only-running")
fi
if [[ -n "${NAME_PREFIX}" ]]; then
  audit_args+=("--name-prefix" "${NAME_PREFIX}")
fi
if [[ "${SSH_CHECKS}" == "true" ]]; then
  audit_args+=("--ssh-checks")
  if [[ -n "${SSH_KEY_PATH}" ]]; then
    audit_args+=("--ssh-key-path" "${SSH_KEY_PATH}")
  fi
fi
if [[ "${COMPARE_BACKEND_DB}" == "true" ]]; then
  audit_args+=("--compare-backend-db")
fi

echo "Running fleet audit..."
"${PYTHON_BIN}" "${audit_args[@]}"

echo "Evaluating strict baseline policy..."
"${PYTHON_BIN}" - "${JSON_OUT}" "${REQUIRE_OPENVPN}" "${REQUIRE_IKEV2}" "${REQUIRE_PRIVATE_NETWORK}" <<'PY'
import json
import sys
from pathlib import Path

json_path = Path(sys.argv[1])
require_openvpn = str(sys.argv[2]).strip().lower() in {"1", "true", "yes", "on"}
require_ikev2 = str(sys.argv[3]).strip().lower() in {"1", "true", "yes", "on"}
require_private_network = str(sys.argv[4]).strip().lower() in {"1", "true", "yes", "on"}

payload = json.loads(json_path.read_text(encoding="utf-8"))
servers = payload.get("servers") or []

failures: list[str] = []
warnings: list[str] = []

def is_active(state: str | None) -> bool:
    return str(state or "").strip().lower() == "active"

for row in servers:
    name = str(row.get("name") or row.get("id") or "<unknown>")
    validation = row.get("validation") or {}
    if not validation.get("has_public_ipv4"):
        failures.append(f"{name}: missing public IPv4")
    if not validation.get("firewall_attached"):
        failures.append(f"{name}: no firewall attached")
    if not validation.get("has_private_network"):
        if require_private_network:
            failures.append(f"{name}: no private network attached")
        else:
            warnings.append(f"{name}: no private network attached")

    host_checks = row.get("host_checks")
    if host_checks is None:
        failures.append(f"{name}: host_checks missing (run with --ssh-checks)")
        continue

    routing = host_checks.get("routing") or {}
    if routing.get("ip_forward_enabled") is not True:
        failures.append(f"{name}: net.ipv4.ip_forward is not enabled")
    if routing.get("nat_has_primary_masquerade") is not True:
        failures.append(f"{name}: no primary MASQUERADE rule on egress interface")

    wireguard = host_checks.get("wireguard") or {}
    if wireguard.get("binary_present") is not True:
        failures.append(f"{name}: WireGuard binary missing")
    if wireguard.get("config_present") is not True:
        failures.append(f"{name}: /etc/wireguard/wg0.conf missing")
    if not is_active(wireguard.get("service_status")):
        failures.append(f"{name}: wg-quick@wg0 service not active")
    if wireguard.get("port_bound") is not True:
        failures.append(f"{name}: WireGuard port not bound")

    if require_openvpn:
        openvpn = host_checks.get("openvpn") or {}
        if openvpn.get("binary_present") is not True:
            failures.append(f"{name}: OpenVPN binary missing")
        if openvpn.get("config_present") is not True:
            failures.append(f"{name}: OpenVPN config missing")
        if openvpn.get("certs_present") is not True:
            failures.append(f"{name}: OpenVPN cert material missing")
        if not is_active(openvpn.get("service_status")):
            failures.append(f"{name}: OpenVPN service not active")
        if not (openvpn.get("port_bound_udp") is True or openvpn.get("port_bound_tcp") is True):
            failures.append(f"{name}: OpenVPN port not bound (udp/tcp)")

    if require_ikev2:
        ikev2 = host_checks.get("ikev2") or {}
        if ikev2.get("binary_present") is not True:
            failures.append(f"{name}: IKEv2 runtime missing (strongSwan/ipsec)")
        if ikev2.get("config_present") is not True:
            failures.append(f"{name}: IKEv2 config missing")
        if ikev2.get("certs_present") is not True:
            failures.append(f"{name}: IKEv2 cert material missing")
        if not is_active(ikev2.get("service_status")):
            failures.append(f"{name}: IKEv2 service not active")
        if ikev2.get("port_bound_udp_500") is not True:
            failures.append(f"{name}: IKEv2 UDP 500 not bound")
        if ikev2.get("port_bound_udp_4500") is not True:
            failures.append(f"{name}: IKEv2 UDP 4500 not bound")

backend_compare = payload.get("backend_registry_compare") or {}
if backend_compare.get("available") is True:
    if backend_compare.get("missing_in_backend"):
        failures.append(
            "backend_registry mismatch: missing_in_backend="
            + ",".join(backend_compare.get("missing_in_backend") or [])
        )
    if backend_compare.get("ip_mismatches"):
        failures.append("backend_registry mismatch: public_ip mismatches present")

print(f"Servers audited: {len(servers)}")
if warnings:
    print("Warnings:")
    for item in warnings:
        print(f"- {item}")

if failures:
    print("Baseline validation FAILED:")
    for item in failures:
        print(f"- {item}")
    raise SystemExit(42)

print("Baseline validation PASSED.")
PY

echo "Strict baseline passed: ${JSON_OUT}"
