#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="${ROOT_DIR}/netopsd"
BIN_DIR="${PROJECT_DIR}/bin"
BINARY_PATH="${BIN_DIR}/securewave-netd"

run_as_root() {
    if [[ "${EUID}" -eq 0 ]]; then
        "$@"
        return 0
    fi
    if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
        sudo "$@"
        return 0
    fi
    return 1
}

echo "[1] Checking Go installation..."
if ! command -v go >/dev/null 2>&1; then
    echo "[INFO] Go not found."
    if ! command -v apt-get >/dev/null 2>&1; then
        echo "[ERROR] apt-get is unavailable; install Go manually and re-run."
        exit 1
    fi
    if ! run_as_root apt-get update; then
        echo "[ERROR] Need root access to install Go. Install golang-go and re-run."
        exit 1
    fi
    if ! run_as_root apt-get install -y golang-go; then
        echo "[ERROR] Failed to install Go."
        exit 1
    fi
fi

echo "[2] Go version:"
go version

if [[ ! -d "${PROJECT_DIR}" ]]; then
    echo "[ERROR] Go project directory not found: ${PROJECT_DIR}"
    exit 1
fi

cd "${PROJECT_DIR}"

echo "[3] Verifying Go module..."
if [[ ! -f "go.mod" ]]; then
    echo "[ERROR] go.mod missing in ${PROJECT_DIR}"
    exit 1
fi

echo "[4] Resolving dependencies..."
go mod tidy

echo "[5] Downloading modules..."
go mod download

echo "[6] Verifying modules..."
go mod verify

echo "[7] Building daemon..."
mkdir -p "${BIN_DIR}"
go build -o "${BINARY_PATH}" ./cmd/securewave-netd

echo "[8] Setting capabilities..."
if command -v setcap >/dev/null 2>&1; then
    if run_as_root setcap cap_net_admin+ep "${BINARY_PATH}"; then
        echo "[INFO] Applied cap_net_admin to ${BINARY_PATH}"
        command -v getcap >/dev/null 2>&1 && getcap "${BINARY_PATH}" || true
    else
        echo "[WARN] setcap requires root; run manually if needed:"
        echo "       sudo setcap cap_net_admin+ep ${BINARY_PATH}"
    fi
else
    echo "[WARN] setcap not installed; install libcap2-bin if capabilities are required."
fi

echo "[9] Done. Binary ready at:"
ls -lh "${BINARY_PATH}"
