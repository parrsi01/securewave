#!/bin/bash
set -euo pipefail

exec bash dev_tools/sandbox/e2e_simulation/run_local_suite.sh "$@"
