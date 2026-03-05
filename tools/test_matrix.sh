#!/usr/bin/env bash

set -u

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
out_dir="tools/test_matrix/out/${timestamp}"
summary_log="${out_dir}/summary.log"
mkdir -p "${out_dir}"

mode="${SECUREWAVE_PROVISIONING_MODE:-local_stub}"
marker_expr='offline or not live'
if [[ "${mode}" == "ssh_real" ]]; then
  marker_expr='not offline'
fi

tmp_output="$(mktemp)"
pytest -q -m "${marker_expr}" 2>&1 | tee "${tmp_output}"
pytest_status=${PIPESTATUS[0]}

summary_line="$(grep -E '[0-9]+ (passed|failed|error|skipped)' "${tmp_output}" | tail -n 1)"
executed_count=0
skipped_count=0

if [[ -n "${summary_line}" ]]; then
  executed_count="$(printf '%s\n' "${summary_line}" | grep -oE '[0-9]+ passed' | awk '{sum += $1} END {print sum + 0}')"
  executed_count="$((executed_count + $(printf '%s\n' "${summary_line}" | grep -oE '[0-9]+ failed' | awk '{sum += $1} END {print sum + 0}')))"
  executed_count="$((executed_count + $(printf '%s\n' "${summary_line}" | grep -oE '[0-9]+ error' | awk '{sum += $1} END {print sum + 0}')))"
  skipped_count="$(printf '%s\n' "${summary_line}" | grep -oE '[0-9]+ skipped' | awk '{sum += $1} END {print sum + 0}')"
fi

backend_result="PASS"
if [[ ${pytest_status} -ne 0 ]]; then
  backend_result="FAIL"
fi

{
  printf 'backend_tests: %s\n' "${backend_result}"
  printf 'skipped_tests_count: %s\n' "${skipped_count}"
  printf 'executed_tests_count: %s\n' "${executed_count}"
} | tee "${summary_log}"

rm -f "${tmp_output}"
exit "${pytest_status}"
