#!/bin/bash
set -euo pipefail

# Backward-compatible wrapper.
exec bash sandbox/e2e_simulation/run_local_suite.sh "$@"

