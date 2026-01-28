#!/usr/bin/env bash
set -euo pipefail

python3 -m http.server --directory static 8080
