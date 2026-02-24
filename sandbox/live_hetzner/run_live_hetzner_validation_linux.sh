#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUN_ID="$(date -u +"%Y%m%d_%H%M%S")"
RUN_DIR="${ROOT_DIR}/artifacts/live_hetzner/${RUN_ID}"

LIVE_API_BASE_URL="${LIVE_API_BASE_URL:-}"
HETZNER_IP="${HETZNER_IP:-}"

STRICT="${STRICT:-1}"
USERS="${LIVE_VALIDATION_USERS:-3}"

PY="${ROOT_DIR}/.venv/bin/python"
if [[ ! -x "${PY}" ]]; then
  PY="python3"
fi

mkdir -p "${RUN_DIR}"

echo "run_id=${RUN_ID}"
echo "run_dir=${RUN_DIR}"

if [[ -z "${LIVE_API_BASE_URL}" ]]; then
  echo "ERROR: LIVE_API_BASE_URL is required (example: https://<hetzner-ip> or https://api.example.com)" >&2
  exit 2
fi

echo "1) Live WireGuard E2E validation (real wg-quick)..."
LIVE_VALIDATION_OUT="${RUN_DIR}/live_validation"
mkdir -p "${LIVE_VALIDATION_OUT}"

E2E_ARGS=(
  "${ROOT_DIR}/dev_tools/sandbox/live_validation/live_e2e_validate.py"
  --output-dir "${LIVE_VALIDATION_OUT}"
  --api-base-url "${LIVE_API_BASE_URL}"
  --users "${USERS}"
  --platform linux
)
if [[ "${STRICT}" == "1" ]]; then
  E2E_ARGS+=(--strict)
fi

set +e
"${PY}" "${E2E_ARGS[@]}" >"${LIVE_VALIDATION_OUT}/stdout.json" 2>"${LIVE_VALIDATION_OUT}/stderr.log"
E2E_RC=$?
set -e

echo "2) Generate live validation readiness summary..."
set +e
"${PY}" "${ROOT_DIR}/dev_tools/sandbox/live_validation/reporting.py" --output-dir "${LIVE_VALIDATION_OUT}" \
  >"${LIVE_VALIDATION_OUT}/readiness_stdout.json" 2>"${LIVE_VALIDATION_OUT}/readiness_stderr.log"
READY_RC=$?
set -e

echo "3) Basic smoke checks (HTTP/HTTPS, SSL, /metrics)..."
bash "${ROOT_DIR}/sandbox/live_hetzner/smoke_http_https.sh" \
  --api-base-url "${LIVE_API_BASE_URL}" \
  ${HETZNER_IP:+--ip "${HETZNER_IP}"} \
  --out "${RUN_DIR}/smoke_http_https.json" \
  >"${RUN_DIR}/smoke_http_https.log" 2>&1 || true

bash "${ROOT_DIR}/sandbox/live_hetzner/ssl_probe.sh" \
  ${HETZNER_IP:+--ip "${HETZNER_IP}"} \
  --api-base-url "${LIVE_API_BASE_URL}" \
  --out "${RUN_DIR}/ssl_probe.json" \
  >"${RUN_DIR}/ssl_probe.log" 2>&1 || true

bash "${ROOT_DIR}/sandbox/live_hetzner/metrics_probe.sh" \
  --api-base-url "${LIVE_API_BASE_URL}" \
  --out "${RUN_DIR}/metrics_probe.json" \
  >"${RUN_DIR}/metrics_probe.log" 2>&1 || true

echo "4) Stripe live activation sanity (safe by default)..."
bash "${ROOT_DIR}/sandbox/live_hetzner/stripe_live_smoke_check.sh" \
  --api-base-url "${LIVE_API_BASE_URL}" \
  --out "${RUN_DIR}/stripe_smoke.json" \
  >"${RUN_DIR}/stripe_smoke.log" 2>&1 || true

echo "5) Domain preview helper (nip.io/sslip.io + cert guidance)..."
bash "${ROOT_DIR}/sandbox/live_hetzner/domain_preview_setup.sh" \
  ${HETZNER_IP:+--ip "${HETZNER_IP}"} \
  --out "${RUN_DIR}/domain_preview.json" \
  >"${RUN_DIR}/domain_preview.log" 2>&1 || true

echo "6) Generate consolidated report..."
"${PY}" "${ROOT_DIR}/sandbox/live_hetzner/generate_live_hetzner_smoke_report.py" \
  --run-dir "${RUN_DIR}" \
  --out "${ROOT_DIR}/artifacts/live_hetzner_smoke_report.md" \
  >"${RUN_DIR}/report_generation.log" 2>&1 || true

echo ""
echo "Outputs:"
echo "- ${ROOT_DIR}/artifacts/live_hetzner_smoke_report.md"
echo "- ${RUN_DIR}/ (raw run artifacts)"
echo ""
echo "Exit codes:"
echo "- live_e2e_validate: ${E2E_RC}"
echo "- readiness_report: ${READY_RC}"
exit 0

