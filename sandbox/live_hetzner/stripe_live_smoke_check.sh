#!/usr/bin/env bash
set -euo pipefail

API_BASE_URL=""
OUT=""

usage() {
  echo "Usage: $0 --api-base-url <url> --out <path>"
  echo "Env:"
  echo "  STRIPE_SMOKE_MODE=test|live (default: test)"
  echo "  ALLOW_LIVE_STRIPE_ACTIONS=true|false (default: false)"
  echo "  STRIPE_WEBHOOK_SECRET=whsec_... (optional; enables signed webhook validation)"
  echo "  STRIPE_SMOKE_PLAN_ID=basic|premium|ultra (default: premium)"
  echo "  STRIPE_SMOKE_BILLING_CYCLE=monthly|yearly (default: monthly)"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --api-base-url) API_BASE_URL="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "${API_BASE_URL}" || -z "${OUT}" ]]; then
  usage
  exit 2
fi

MODE="${STRIPE_SMOKE_MODE:-test}"
ALLOW_LIVE="${ALLOW_LIVE_STRIPE_ACTIONS:-false}"
PLAN_ID="${STRIPE_SMOKE_PLAN_ID:-premium}"
CYCLE="${STRIPE_SMOKE_BILLING_CYCLE:-monthly}"
WEBHOOK_SECRET="${STRIPE_WEBHOOK_SECRET:-}"
STRIPE_KEY="${STRIPE_SECRET_KEY:-}"

ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

status_code_from_headers() {
  local headers_file="$1"
  local code
  code="$(grep -m1 -E "HTTP/[0-9.]+ [0-9]{3}" "${headers_file}" | awk '{print $2}' || true)"
  [[ "${code}" =~ ^[0-9]{3}$ ]] || code="000"
  echo "${code}"
}

json_preview_file() {
  local path="$1"
  local max="${2:-900}"
  python3 - <<PY
import json
from pathlib import Path
p=Path("${path}")
raw=p.read_text(encoding="utf-8", errors="ignore").strip() if p.exists() else ""
if not raw:
  print("")
  raise SystemExit(0)
try:
  d=json.loads(raw)
  print(json.dumps(d)[:${max}])
except Exception:
  print(raw[:${max}])
PY
}

stripe_status_code="000"
stripe_status_body=""
backend_mode=""
action_blocked="false"

stripe_api_status="skipped"
stripe_api_livemode=""
stripe_api_body=""

checkout_code="skipped"
checkout_body=""
webhook_attempted="false"
webhook_code="skipped"
webhook_body=""

auth_email="stripe.smoke.$(date +%s)@example.com"
auth_pass="${LIVE_VALIDATION_PASSWORD:-LiveValidate#123}"
token=""
me_id=""

# 1) Backend stripe status (no auth)
curl -sS -D "${tmp_dir}/stripe_status_hdr.txt" -o "${tmp_dir}/stripe_status_body.json" \
  --connect-timeout 6 --max-time 18 \
  "${API_BASE_URL%/}/api/billing/stripe-status" 2>/dev/null || true
stripe_status_code="$(status_code_from_headers "${tmp_dir}/stripe_status_hdr.txt")"
stripe_status_body="$(json_preview_file "${tmp_dir}/stripe_status_body.json" 600)"
backend_mode="$(python3 - <<PY
import json
from pathlib import Path
try:
  d=json.loads(Path("${tmp_dir}/stripe_status_body.json").read_text(encoding="utf-8"))
except Exception:
  d={}
print((d.get("mode") or "").strip())
PY
)"

# Fallback for deployments that only expose the /api/payments stripe router.
if [[ "${stripe_status_code}" == "404" || "${stripe_status_code}" == "000" ]]; then
  curl -sS -D "${tmp_dir}/stripe_status_hdr.txt" -o "${tmp_dir}/stripe_status_body.json" \
    --connect-timeout 6 --max-time 18 \
    "${API_BASE_URL%/}/api/payments/stripe/plans" 2>/dev/null || true
  stripe_status_code="$(status_code_from_headers "${tmp_dir}/stripe_status_hdr.txt")"
  stripe_status_body="$(json_preview_file "${tmp_dir}/stripe_status_body.json" 600)"
  backend_mode=""
fi

# Optional: validate Stripe key directly (read-only).
if [[ -n "${STRIPE_KEY}" ]]; then
  # Stripe uses HTTP basic auth with the secret key as username and blank password.
  curl -sS -D "${tmp_dir}/stripe_api_hdr.txt" -o "${tmp_dir}/stripe_api_body.json" \
    --connect-timeout 6 --max-time 18 \
    -u "${STRIPE_KEY}:" \
    "https://api.stripe.com/v1/account" 2>/dev/null || true
  stripe_api_status="$(status_code_from_headers "${tmp_dir}/stripe_api_hdr.txt")"
  stripe_api_body="$(json_preview_file "${tmp_dir}/stripe_api_body.json" 700)"
  stripe_api_livemode="$(python3 - <<PY
import json
from pathlib import Path
try:
  d=json.loads(Path("${tmp_dir}/stripe_api_body.json").read_text(encoding="utf-8"))
except Exception:
  d={}
print(str(d.get("livemode") or ""))
PY
)"
fi

if [[ "${backend_mode}" == "live" && "${ALLOW_LIVE}" != "true" ]]; then
  action_blocked="true"
fi

if [[ "${action_blocked}" != "true" ]]; then
  # 2) Register or login -> token
  reg_json="$(printf '{"email":"%s","password":"%s","password_confirm":"%s"}' "${auth_email}" "${auth_pass}" "${auth_pass}")"
  curl -sS -D "${tmp_dir}/auth_hdr.txt" -o "${tmp_dir}/auth_body.json" \
    -H "Content-Type: application/json" \
    --connect-timeout 6 --max-time 18 \
    -X POST "${API_BASE_URL%/}/api/auth/register" -d "${reg_json}" 2>/dev/null || true
  token="$(python3 - <<PY
import json
from pathlib import Path
try:
  d=json.loads(Path("${tmp_dir}/auth_body.json").read_text(encoding="utf-8"))
except Exception:
  d={}
print(d.get("access_token") or "")
PY
)"

  if [[ -z "${token}" ]]; then
    login_json="$(printf '{"email":"%s","password":"%s"}' "${auth_email}" "${auth_pass}")"
    curl -sS -D "${tmp_dir}/auth_hdr.txt" -o "${tmp_dir}/auth_body.json" \
      -H "Content-Type: application/json" \
      --connect-timeout 6 --max-time 18 \
      -X POST "${API_BASE_URL%/}/api/auth/login" -d "${login_json}" 2>/dev/null || true
    token="$(python3 - <<PY
import json
from pathlib import Path
try:
  d=json.loads(Path("${tmp_dir}/auth_body.json").read_text(encoding="utf-8"))
except Exception:
  d={}
print(d.get("access_token") or "")
PY
)"
  fi

  if [[ -n "${token}" ]]; then
    # 3) /api/auth/me to get user_id for optional webhook metadata
    curl -sS -D "${tmp_dir}/me_hdr.txt" -o "${tmp_dir}/me_body.json" \
      -H "Authorization: Bearer ${token}" \
      --connect-timeout 6 --max-time 18 \
      "${API_BASE_URL%/}/api/auth/me" 2>/dev/null || true
    me_id="$(python3 - <<PY
import json
from pathlib import Path
try:
  d=json.loads(Path("${tmp_dir}/me_body.json").read_text(encoding="utf-8"))
except Exception:
  d={}
print(d.get("id") or "")
PY
)"

    # 4) Create checkout session
    req="$(printf '{"plan_id":"%s","billing_cycle":"%s","trial_days":0}' "${PLAN_ID}" "${CYCLE}")"
    curl -sS -D "${tmp_dir}/checkout_hdr.txt" -o "${tmp_dir}/checkout_body.json" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${token}" \
      --connect-timeout 6 --max-time 18 \
      -X POST "${API_BASE_URL%/}/api/billing/checkout-session" -d "${req}" 2>/dev/null || true
    checkout_code="$(status_code_from_headers "${tmp_dir}/checkout_hdr.txt")"
    checkout_body="$(json_preview_file "${tmp_dir}/checkout_body.json" 900)"
    if [[ "${checkout_code}" == "404" || "${checkout_code}" == "000" ]]; then
      curl -sS -D "${tmp_dir}/checkout_hdr.txt" -o "${tmp_dir}/checkout_body.json" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${token}" \
        --connect-timeout 6 --max-time 18 \
        -X POST "${API_BASE_URL%/}/api/payments/stripe/create-checkout-session" -d "${req}" 2>/dev/null || true
      checkout_code="$(status_code_from_headers "${tmp_dir}/checkout_hdr.txt")"
      checkout_body="$(json_preview_file "${tmp_dir}/checkout_body.json" 900)"
    fi

    # 5) Signed webhook validation (optional)
    if [[ -n "${WEBHOOK_SECRET}" && -n "${me_id}" ]]; then
      webhook_attempted="true"
      now_epoch="$(date +%s)"
      event_id="evt_sw_smoke_${now_epoch}"
      sub_id="sub_sw_smoke_${now_epoch}"
      payload="$(python3 - <<PY
import json, time
obj={
  "id": "${event_id}",
  "type": "customer.subscription.created",
  "created": int(time.time()),
  "data": {"object": {
    "id": "${sub_id}",
    "status": "trialing",
    "metadata": {"securewave_user_id": str("${me_id}"), "plan_id": "${PLAN_ID}", "billing_cycle": "${CYCLE}"},
    "items": {"data": []}
  }}
}
print(json.dumps(obj, separators=(",",":")))
PY
)"
      signed_payload="${now_epoch}.${payload}"
      if ! command -v openssl >/dev/null 2>&1; then
        webhook_code="skipped"
        webhook_body="openssl_not_found"
      else
        sig="$(printf "%s" "${signed_payload}" | openssl dgst -sha256 -hmac "${WEBHOOK_SECRET}" | awk '{print $2}')"
        stripe_sig="t=${now_epoch},v1=${sig}"
        curl -sS -D "${tmp_dir}/wh_hdr.txt" -o "${tmp_dir}/wh_body.json" \
          -H "Content-Type: application/json" \
          -H "Stripe-Signature: ${stripe_sig}" \
          --connect-timeout 6 --max-time 18 \
          -X POST "${API_BASE_URL%/}/api/billing/webhooks/stripe" -d "${payload}" 2>/dev/null || true
        webhook_code="$(status_code_from_headers "${tmp_dir}/wh_hdr.txt")"
        webhook_body="$(json_preview_file "${tmp_dir}/wh_body.json" 900)"
        if [[ "${webhook_code}" == "404" || "${webhook_code}" == "000" ]]; then
          curl -sS -D "${tmp_dir}/wh_hdr.txt" -o "${tmp_dir}/wh_body.json" \
            -H "Content-Type: application/json" \
            -H "Stripe-Signature: ${stripe_sig}" \
            --connect-timeout 6 --max-time 18 \
            -X POST "${API_BASE_URL%/}/api/payments/stripe/webhook" -d "${payload}" 2>/dev/null || true
          webhook_code="$(status_code_from_headers "${tmp_dir}/wh_hdr.txt")"
          webhook_body="$(json_preview_file "${tmp_dir}/wh_body.json" 900)"
        fi
      fi
    fi
  fi
fi

python3 - <<PY >"${OUT}"
import json
payload = {
  "generated_at": "${ts}",
  "api_base_url": "${API_BASE_URL}",
  "stripe_api": {
    "http_status": "${stripe_api_status}",
    "livemode": "${stripe_api_livemode}",
    "body_preview": ${json.dumps(stripe_api_body)},
  },
  "backend_stripe_status": {
    "http_status": "${stripe_status_code}",
    "body_preview": ${json.dumps(stripe_status_body)},
  },
  "backend_mode": "${backend_mode}",
  "requested_mode": "${MODE}",
  "live_actions_blocked": ${"true" if action_blocked == "true" else "false"},
  "checkout_session": {
    "http_status": "${checkout_code}",
    "body_preview": ${json.dumps(checkout_body)},
  },
  "webhook_validation": {
    "attempted": ${"true" if webhook_attempted == "true" else "false"},
    "http_status": "${webhook_code}",
    "body_preview": ${json.dumps(webhook_body)},
  },
  "notes": [
    "For safety, live Stripe actions are blocked unless ALLOW_LIVE_STRIPE_ACTIONS=true and backend reports mode=live.",
    "Webhook validation uses STRIPE_WEBHOOK_SECRET (endpoint secret) to sign a synthetic event; it may mutate DB state.",
  ],
}
print(json.dumps(payload, indent=2))
PY
