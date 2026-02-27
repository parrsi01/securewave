#!/usr/bin/env bash
set -euo pipefail

CONNECT_CMD=""
DISCONNECT_CMD=""
SKIP_INTERACTIVE=0
STOP_AFTER_BASELINE=0
CONNECT_CMD_STATUS=0
DISCONNECT_CMD_STATUS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --connect-cmd)
      CONNECT_CMD="${2:-}"
      shift 2
      ;;
    --disconnect-cmd)
      DISCONNECT_CMD="${2:-}"
      shift 2
      ;;
    --skip-interactive)
      SKIP_INTERACTIVE=1
      shift
      ;;
    --stop-after-baseline)
      STOP_AFTER_BASELINE=1
      shift
      ;;
    -h|--help)
      cat <<'USAGE'
Usage: tunnel_probe.sh [--connect-cmd "<cmd>"] [--disconnect-cmd "<cmd>"] [--skip-interactive] [--stop-after-baseline]

Collects baseline and post-connect evidence bundles for Linux VPN tunnel validation.
If connect/disconnect commands are not provided, prompts for manual UI actions.
USAGE
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OUT_ROOT="${SCRIPT_DIR}/out"
RUN_ID="$(date +%Y%m%d_%H%M%S)"
OUT_DIR="${OUT_ROOT}/${RUN_ID}"
mkdir -p "${OUT_DIR}/baseline" "${OUT_DIR}/post_connect" "${OUT_DIR}/post_disconnect" "${OUT_DIR}/pcap"

log() { printf -- '[probe] %s\n' "$*"; }
warn() { printf -- '[probe][warn] %s\n' "$*" >&2; }

have_cmd() { command -v "$1" >/dev/null 2>&1; }

run_capture() {
  local outfile="$1"; shift
  {
    printf -- '$ %s\n' "$*"
    "$@"
  } >"${outfile}" 2>&1 || {
    printf -- '\n[exit=%s]\n' "$?" >>"${outfile}"
    return 0
  }
}

run_capture_shell() {
  local outfile="$1"; shift
  local cmd="$*"
  {
    printf -- '$ %s\n' "${cmd}"
    bash -lc "${cmd}"
  } >"${outfile}" 2>&1 || {
    printf -- '\n[exit=%s]\n' "$?" >>"${outfile}"
    return 0
  }
}

run_maybe_sudo_shell() {
  local outfile="$1"; shift
  local cmd="$*"
  if have_cmd sudo && sudo -n true >/dev/null 2>&1; then
    {
      printf -- '$ sudo -n %s\n' "${cmd}"
      sudo -n bash -lc "${cmd}"
    } >"${outfile}" 2>&1 || {
      printf -- '\n[exit=%s]\n' "$?" >>"${outfile}"
      return 0
    }
  else
    printf -- '[skip] sudo unavailable or requires password for: %s\n' "${cmd}" >"${outfile}"
  fi
}

redact_wg_show() {
  local infile="$1" outfile="$2"
  if [[ -f "$infile" ]]; then
    sed -E 's/^( *private key:).*/\1 [REDACTED]/I' "$infile" >"$outfile"
  else
    printf -- '[missing input]\n' >"$outfile"
  fi
}

capture_egress() {
  local bundle_dir="$1"
  if have_cmd curl; then
    run_capture_shell "${bundle_dir}/egress_ifconfig_me.txt" "curl -fsS --max-time 8 https://ifconfig.me || true"
    run_capture_shell "${bundle_dir}/egress_ipify.txt" "curl -fsS --max-time 8 https://api.ipify.org || true"
    run_capture_shell "${bundle_dir}/egress_cloudflare_trace.txt" "curl -fsS --max-time 8 https://1.1.1.1/cdn-cgi/trace || true"
  else
    printf -- '[skip] curl not installed\n' >"${bundle_dir}/egress_ifconfig_me.txt"
    cp "${bundle_dir}/egress_ifconfig_me.txt" "${bundle_dir}/egress_ipify.txt"
    cp "${bundle_dir}/egress_ifconfig_me.txt" "${bundle_dir}/egress_cloudflare_trace.txt"
  fi
}

capture_dns_checks() {
  local bundle_dir="$1"
  if have_cmd getent; then
    run_capture_shell "${bundle_dir}/dns_lookup_example.txt" "getent ahosts example.com | head -n 6 || true"
  elif have_cmd resolvectl; then
    run_capture_shell "${bundle_dir}/dns_lookup_example.txt" "resolvectl query example.com || true"
  else
    printf -- '[skip] no DNS lookup command available (getent/resolvectl)\n' >"${bundle_dir}/dns_lookup_example.txt"
  fi

  if have_cmd curl; then
    run_capture_shell "${bundle_dir}/dns_https_check.txt" "curl -fsS --max-time 8 -o /dev/null -w 'http_code=%{http_code}\\n' https://example.com || true"
  else
    printf -- '[skip] curl not installed\n' >"${bundle_dir}/dns_https_check.txt"
  fi
}

detect_probe_iface() {
  if ip link show wg0 >/dev/null 2>&1; then
    printf -- 'wg0'
    return
  fi
  if ip link show sw-wg >/dev/null 2>&1; then
    printf -- 'sw-wg'
    return
  fi
  if ip link show tun0 >/dev/null 2>&1; then
    printf -- 'tun0'
    return
  fi
  printf -- ''
}

capture_tcpdump_sample() {
  local bundle_name="$1"
  local iface
  iface="$(detect_probe_iface)"
  local out_txt="${OUT_DIR}/${bundle_name}/tcpdump_sample_note.txt"
  if [[ -z "$iface" ]]; then
    printf -- '[skip] no wg0/sw-wg/tun0 interface present\n' >"${out_txt}"
    return 0
  fi
  if ! have_cmd tcpdump; then
    printf -- '[skip] tcpdump not installed\n' >"${out_txt}"
    return 0
  fi
  if ! have_cmd sudo || ! sudo -n true >/dev/null 2>&1; then
    printf -- '[skip] sudo unavailable or requires password; tcpdump capture skipped on %s\n' "$iface" >"${out_txt}"
    return 0
  fi

  local pcap="${OUT_DIR}/pcap/${bundle_name}_${iface}.pcap"
  {
    echo "iface=${iface}"
    echo "pcap=${pcap}"
    echo "capturing ~3s while sending one ping attempt"
  } >"${out_txt}"

  sudo -n timeout 3 tcpdump -i "$iface" -w "$pcap" >/dev/null 2>"${OUT_DIR}/${bundle_name}/tcpdump_stderr.txt" &
  local cap_pid=$!
  sleep 1
  if have_cmd ping; then
    ping -c 1 -W 1 1.1.1.1 >/dev/null 2>&1 || true
  fi
  wait "$cap_pid" || true
}

capture_bundle() {
  local bundle_name="$1"
  local bundle_dir="${OUT_DIR}/${bundle_name}"
  mkdir -p "${bundle_dir}"
  log "capturing bundle: ${bundle_name}"

  run_capture "${bundle_dir}/date.txt" date -Is
  run_capture "${bundle_dir}/uname.txt" uname -a
  run_capture "${bundle_dir}/ip_addr.txt" ip addr
  run_capture "${bundle_dir}/ip_route.txt" ip route
  if have_cmd resolvectl; then
    run_capture "${bundle_dir}/resolvectl_status.txt" resolvectl status
  else
    printf -- '[skip] resolvectl not installed\n' >"${bundle_dir}/resolvectl_status.txt"
  fi

  if have_cmd wg; then
    run_capture "${bundle_dir}/wg_show_raw.txt" wg show
    redact_wg_show "${bundle_dir}/wg_show_raw.txt" "${bundle_dir}/wg_show.txt"
    rm -f "${bundle_dir}/wg_show_raw.txt"
  else
    printf -- '[skip] wg not installed\n' >"${bundle_dir}/wg_show.txt"
  fi

  capture_egress "${bundle_dir}"
  capture_dns_checks "${bundle_dir}"

  run_capture "${bundle_dir}/ip_route_get_1.1.1.1.txt" ip route get 1.1.1.1
  run_capture "${bundle_dir}/ip_route_get_8.8.8.8.txt" ip route get 8.8.8.8
  run_capture "${bundle_dir}/ip_rule_show.txt" ip rule show

  if have_cmd nft; then
    run_maybe_sudo_shell "${bundle_dir}/firewall_rules_excerpt.txt" "nft list ruleset | head -120"
  elif have_cmd iptables; then
    run_maybe_sudo_shell "${bundle_dir}/firewall_rules_excerpt.txt" "iptables -S | head -120"
  else
    printf -- '[skip] neither nft nor iptables found\n' >"${bundle_dir}/firewall_rules_excerpt.txt"
  fi

  capture_tcpdump_sample "${bundle_name}"
}

extract_first_line_text() {
  local file="$1"
  [[ -f "$file" ]] || { printf -- ''; return; }
  sed -n '2,$p' "$file" | tr -d '\r' | awk 'NF{print; exit}'
}

extract_ip_route_summary() {
  local file="$1"
  [[ -f "$file" ]] || { printf -- ''; return; }
  awk '/^\$ /{next} /^default /{print; exit}' "$file"
}

extract_route_get_iface() {
  local file="$1"
  [[ -f "$file" ]] || { printf -- ''; return; }
  awk '/ dev /{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}' "$file"
}

extract_resolved_ip() {
  local file="$1"
  [[ -f "$file" ]] || { printf -- ''; return; }
  local v
  v="$(sed -n '2,$p' "$file" | tr -d '\r' | awk 'NF{print; exit}')"
  printf -- '%s' "$v" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1 || true
}

extract_dns_resolver() {
  local file="$1"
  [[ -f "$file" ]] || { printf -- ''; return; }
  awk '
    /Current DNS Server:/ {
      print $4
      exit
    }
    /DNS Servers:/ {
      for (i = 3; i <= NF; i++) {
        if ($i != "") {
          print $i
          exit
        }
      }
    }
  ' "$file"
}

dns_lookup_success() {
  local file="$1"
  [[ -f "$file" ]] || { printf -- 'unknown'; return; }
  if grep -Eq '([0-9]{1,3}\.){3}[0-9]{1,3}' "$file"; then
    printf -- 'yes'
    return
  fi
  if grep -Eqi 'NXDOMAIN|SERVFAIL|not known|no address|failed' "$file"; then
    printf -- 'no'
    return
  fi
  printf -- 'unknown'
}

dns_https_success() {
  local file="$1"
  [[ -f "$file" ]] || { printf -- 'unknown'; return; }
  local code
  code="$(grep -Eo 'http_code=[0-9]{3}' "$file" | head -1 | cut -d= -f2 || true)"
  if [[ -z "$code" ]]; then
    printf -- 'unknown'
    return
  fi
  if [[ "$code" =~ ^[234][0-9][0-9]$ ]]; then
    printf -- 'yes'
    return
  fi
  printf -- 'no'
}

generate_report() {
  local report="${OUT_DIR}/REPORT.md"
  local b="${OUT_DIR}/baseline"
  local p="${OUT_DIR}/post_connect"
  local d="${OUT_DIR}/post_disconnect"
  local connect_cmd_status disconnect_cmd_status
  connect_cmd_status="$(tr -d '\r\n' <"${OUT_DIR}/connect_cmd_exit_status.txt" 2>/dev/null || printf -- 'n/a')"
  disconnect_cmd_status="$(tr -d '\r\n' <"${OUT_DIR}/disconnect_cmd_exit_status.txt" 2>/dev/null || printf -- 'n/a')"

  local b_default p_default b_ip p_ip b_get1_iface p_get1_iface
  local b_dns_resolver p_dns_resolver
  b_default="$(extract_ip_route_summary "${b}/ip_route.txt")"
  p_default="$(extract_ip_route_summary "${p}/ip_route.txt")"
  b_ip="$(extract_resolved_ip "${b}/egress_ipify.txt")"
  p_ip="$(extract_resolved_ip "${p}/egress_ipify.txt")"
  b_get1_iface="$(extract_route_get_iface "${b}/ip_route_get_1.1.1.1.txt")"
  p_get1_iface="$(extract_route_get_iface "${p}/ip_route_get_1.1.1.1.txt")"
  b_dns_resolver="$(extract_dns_resolver "${b}/resolvectl_status.txt")"
  p_dns_resolver="$(extract_dns_resolver "${p}/resolvectl_status.txt")"

  local iface_present="no"
  if grep -Eq 'interface: (wg0|sw-wg|tun0)' "${p}/wg_show.txt" 2>/dev/null ||
      grep -Eq '^[0-9]+: (wg0|sw-wg|tun0):' "${p}/ip_addr.txt" 2>/dev/null; then
    iface_present="yes"
  fi
  local wg_handshake="unknown"
  if grep -Eiq 'latest handshake: .*(second|minute|hour|day)' "${p}/wg_show.txt" 2>/dev/null; then
    wg_handshake="yes"
  elif grep -Eiq 'latest handshake: never' "${p}/wg_show.txt" 2>/dev/null; then
    wg_handshake="no"
  fi
  local default_changed="no"
  [[ "${b_default}" != "${p_default}" ]] && default_changed="yes"
  local egress_changed="unknown"
  if [[ -n "${b_ip}" && -n "${p_ip}" ]]; then
    [[ "${b_ip}" != "${p_ip}" ]] && egress_changed="yes" || egress_changed="no"
  fi
  local route_iface_changed="no"
  [[ "${b_get1_iface}" != "${p_get1_iface}" ]] && route_iface_changed="yes"
  local policy_route_present_post="no"
  if grep -Eq '51820|fwmark' "${p}/ip_rule_show.txt" 2>/dev/null; then
    policy_route_present_post="yes"
  fi
  local routing_mode="no_tunnel_routing_detected"
  if [[ "${default_changed}" == "yes" ]]; then
    routing_mode="full_tunnel_default_route"
  elif [[ "${policy_route_present_post}" == "yes" && "${route_iface_changed}" == "yes" ]]; then
    routing_mode="policy_tunnel_rule_table"
  elif [[ "${route_iface_changed}" == "yes" ]]; then
    routing_mode="partial_route_override"
  fi
  local dns_changed="unknown"
  if [[ -f "${b}/resolvectl_status.txt" && -f "${p}/resolvectl_status.txt" ]]; then
    if cmp -s "${b}/resolvectl_status.txt" "${p}/resolvectl_status.txt"; then
      dns_changed="no"
    else
      dns_changed="yes"
    fi
  fi
  local dns_resolver_changed="unknown"
  if [[ -n "${b_dns_resolver}" && -n "${p_dns_resolver}" ]]; then
    [[ "${b_dns_resolver}" != "${p_dns_resolver}" ]] && dns_resolver_changed="yes" || dns_resolver_changed="no"
  fi
  local dns_lookup_post dns_https_post dns_query_working
  dns_lookup_post="$(dns_lookup_success "${p}/dns_lookup_example.txt")"
  dns_https_post="$(dns_https_success "${p}/dns_https_check.txt")"
  dns_query_working="unknown"
  if [[ "${dns_lookup_post}" == "yes" || "${dns_https_post}" == "yes" ]]; then
    dns_query_working="yes"
  elif [[ "${dns_lookup_post}" == "no" && "${dns_https_post}" == "no" ]]; then
    dns_query_working="no"
  fi
  local disconnected_iface_gone="unknown"
  if [[ -f "${d}/ip_addr.txt" ]]; then
    if grep -Eq '^[0-9]+: (wg0|sw-wg|tun0):' "${d}/ip_addr.txt" 2>/dev/null; then
      disconnected_iface_gone="no"
    else
      disconnected_iface_gone="yes"
    fi
  fi

  {
    printf -- '# Tunnel Probe Report\n\n'
    printf -- '- Run ID: `%s`\n' "${RUN_ID}"
    printf -- '- Output dir: `%s`\n\n' "${OUT_DIR}"

    printf -- '## Summary Verdicts\n\n'
    printf -- '- Connect command exit status: **%s**\n' "${connect_cmd_status}"
    printf -- '- Disconnect command exit status: **%s**\n' "${disconnect_cmd_status}"
    printf -- '- Tunnel up (wg/tun interface visible post-connect): **%s**\n' "${iface_present}"
    printf -- '- WireGuard handshake observed (if WireGuard): **%s**\n' "${wg_handshake}"
    printf -- '- Default route changed: **%s**\n' "${default_changed}"
    printf -- '- Policy route/rule present post-connect (table 51820/fwmark): **%s**\n' "${policy_route_present_post}"
    printf -- '- Routing mode inferred: **%s**\n' "${routing_mode}"
    printf -- '- Egress IP changed: **%s**\n' "${egress_changed}"
    printf -- '- DNS state changed: **%s**\n' "${dns_changed}"
    printf -- '- DNS resolver changed: **%s**\n' "${dns_resolver_changed}"
    printf -- '- DNS query validation post-connect: **%s**\n' "${dns_query_working}"
    printf -- '- Route decision (`ip route get 1.1.1.1`) interface changed: **%s**\n' "${route_iface_changed}"
    printf -- '- Post-disconnect tunnel interface removed: **%s**\n' "${disconnected_iface_gone}"
    printf -- '- Leaks: **manual review required** (`egress_cloudflare_trace.txt`, route/firewall excerpts, post_disconnect bundle)\n\n'

    if [[ "${iface_present}" == "yes" && "${egress_changed}" == "no" ]]; then
      printf -- '### Likely Causes (Tunnel Interface Present but Egress Unchanged)\n\n'
      printf -- '- Default/policy routing was not activated (`post_connect/ip_rule_show.txt`, `post_connect/ip_route.txt`).\n'
      printf -- '- WireGuard handshake/server reachability failed (`post_connect/wg_show.txt`).\n'
      printf -- '- Server NAT/forwarding is not configured (`ip_forward=0` or NAT rules missing).\n'
      printf -- '- `AllowedIPs` is not full-tunnel or routing hooks did not run.\n\n'
    fi
    if [[ "${dns_query_working}" == "no" ]]; then
      printf -- '### Likely Causes (DNS Lookup Failed Post-connect)\n\n'
      printf -- '- Tunnel DNS servers were not applied or are unreachable (`post_connect/resolvectl_status.txt`).\n'
      printf -- '- Policy routing sends DNS traffic outside the tunnel while local resolver blocks plain DNS.\n'
      printf -- '- Upstream resolver outage or firewall drop for DNS/HTTPS on the tunnel path.\n\n'
    fi

    printf -- '## Baseline vs Post-connect\n\n'
    printf -- '| Signal | Baseline | Post-connect |\n'
    printf -- '|---|---|---|\n'
    printf -- '| Default route | `%s` | `%s` |\n' "${b_default:-n/a}" "${p_default:-n/a}"
    printf -- '| Routing mode | `n/a` | `%s` |\n' "${routing_mode}"
    printf -- '| `ip route get 1.1.1.1` iface | `%s` | `%s` |\n' "${b_get1_iface:-n/a}" "${p_get1_iface:-n/a}"
    printf -- '| Egress IP (ipify) | `%s` | `%s` |\n' "${b_ip:-n/a}" "${p_ip:-n/a}"
    printf -- '| DNS resolver (primary) | `%s` | `%s` |\n' "${b_dns_resolver:-n/a}" "${p_dns_resolver:-n/a}"
    printf -- '| DNS query validation | `%s` | `%s` |\n' "$(dns_lookup_success "${b}/dns_lookup_example.txt")" "${dns_query_working}"
    printf -- '\n'

    printf -- '## Post-disconnect Snapshot\n\n'
    printf -- '- Default route: `%s`\n' "$(extract_ip_route_summary "${d}/ip_route.txt")"
    printf -- '- `ip route get 1.1.1.1` iface: `%s`\n' "$(extract_route_get_iface "${d}/ip_route_get_1.1.1.1.txt")"
    printf -- '- Egress IP (ipify): `%s`\n\n' "$(extract_resolved_ip "${d}/egress_ipify.txt")"

    printf -- '## Captured Files\n\n'
    printf -- '### Baseline (`baseline/`)\n\n'
    printf -- '- `baseline/date.txt`\n- `baseline/uname.txt`\n- `baseline/ip_addr.txt`\n- `baseline/ip_route.txt`\n'
    printf -- '- `baseline/resolvectl_status.txt`\n- `baseline/wg_show.txt`\n'
    printf -- '- `baseline/egress_ifconfig_me.txt`\n- `baseline/egress_ipify.txt`\n- `baseline/egress_cloudflare_trace.txt`\n'
    printf -- '- `baseline/dns_lookup_example.txt`\n- `baseline/dns_https_check.txt`\n'
    printf -- '- `baseline/ip_route_get_1.1.1.1.txt`\n- `baseline/ip_route_get_8.8.8.8.txt`\n- `baseline/ip_rule_show.txt`\n'
    printf -- '- `baseline/firewall_rules_excerpt.txt`\n- `baseline/tcpdump_sample_note.txt`\n\n'

    printf -- '### Post-connect (`post_connect/`)\n\n'
    printf -- '- `post_connect/date.txt`\n- `post_connect/uname.txt`\n- `post_connect/ip_addr.txt`\n- `post_connect/ip_route.txt`\n'
    printf -- '- `post_connect/resolvectl_status.txt`\n- `post_connect/wg_show.txt`\n'
    printf -- '- `post_connect/egress_ifconfig_me.txt`\n- `post_connect/egress_ipify.txt`\n- `post_connect/egress_cloudflare_trace.txt`\n'
    printf -- '- `post_connect/dns_lookup_example.txt`\n- `post_connect/dns_https_check.txt`\n'
    printf -- '- `post_connect/ip_route_get_1.1.1.1.txt`\n- `post_connect/ip_route_get_8.8.8.8.txt`\n- `post_connect/ip_rule_show.txt`\n'
    printf -- '- `post_connect/firewall_rules_excerpt.txt`\n- `post_connect/tcpdump_sample_note.txt`\n\n'

    printf -- '### Post-disconnect (`post_disconnect/`)\n\n'
    printf -- '- `post_disconnect/date.txt`\n- `post_disconnect/uname.txt`\n- `post_disconnect/ip_addr.txt`\n- `post_disconnect/ip_route.txt`\n'
    printf -- '- `post_disconnect/resolvectl_status.txt`\n- `post_disconnect/wg_show.txt`\n'
    printf -- '- `post_disconnect/egress_ifconfig_me.txt`\n- `post_disconnect/egress_ipify.txt`\n- `post_disconnect/egress_cloudflare_trace.txt`\n'
    printf -- '- `post_disconnect/dns_lookup_example.txt`\n- `post_disconnect/dns_https_check.txt`\n'
    printf -- '- `post_disconnect/ip_route_get_1.1.1.1.txt`\n- `post_disconnect/ip_route_get_8.8.8.8.txt`\n- `post_disconnect/ip_rule_show.txt`\n'
    printf -- '- `post_disconnect/firewall_rules_excerpt.txt`\n- `post_disconnect/tcpdump_sample_note.txt`\n\n'

    printf -- '### PCAPs (`pcap/`)\n\n'
    printf -- '- Optional interface captures if sudo+tcpdump were available.\n'
    printf -- '- `connect_cmd_exit_status.txt`\n'
    printf -- '- `disconnect_cmd_exit_status.txt`\n'
  } >"${report}"
}

manual_pause() {
  local prompt="$1"
  if [[ "${SKIP_INTERACTIVE}" -eq 1 ]]; then
    log "skip-interactive enabled: ${prompt}"
    return 0
  fi
  printf -- '\n%s\nPress Enter to continue...' "$prompt"
  read -r _
}

capture_bundle "baseline"

if [[ "${STOP_AFTER_BASELINE}" -eq 1 ]]; then
  cat <<EOF

[probe] Baseline capture completed.
[probe] Output: ${OUT_DIR}

Next steps:
1. Launch SecureWave app and log in.
2. Ensure auto-connect is ON (if testing startup behavior), or manually press Connect.
3. Re-run this probe without --stop-after-baseline (or with --connect-cmd/--disconnect-cmd).
4. Example manual full run:
   ${SCRIPT_DIR}/tunnel_probe.sh

EOF
  exit 0
fi

if [[ -n "${CONNECT_CMD}" ]]; then
  log "running connect command"
  set +e
  bash -lc "${CONNECT_CMD}"
  CONNECT_CMD_STATUS=$?
  set -e
  if [[ "${CONNECT_CMD_STATUS}" -ne 0 ]]; then
    warn "connect command exited non-zero (${CONNECT_CMD_STATUS})"
  fi
else
  manual_pause "[manual action] In the SecureWave app, click Connect (WireGuard preferred), wait until the app shows connected/protected."
fi

capture_bundle "post_connect"

if [[ -n "${DISCONNECT_CMD}" ]]; then
  log "running disconnect command"
  set +e
  bash -lc "${DISCONNECT_CMD}"
  DISCONNECT_CMD_STATUS=$?
  set -e
  if [[ "${DISCONNECT_CMD_STATUS}" -ne 0 ]]; then
    warn "disconnect command exited non-zero (${DISCONNECT_CMD_STATUS})"
  fi
else
  manual_pause "[manual action] In the SecureWave app, click Disconnect after reviewing the app state."
fi

capture_bundle "post_disconnect"
printf -- '%s\n' "${CONNECT_CMD_STATUS}" >"${OUT_DIR}/connect_cmd_exit_status.txt"
printf -- '%s\n' "${DISCONNECT_CMD_STATUS}" >"${OUT_DIR}/disconnect_cmd_exit_status.txt"
generate_report

cat <<EOF

[probe] Completed.
[probe] Output directory: ${OUT_DIR}
[probe] Report: ${OUT_DIR}/REPORT.md

EOF
