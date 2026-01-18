#!/bin/bash
#
# SecureWave VPN Test Suite - Runner Script
# ==========================================
#
# Usage:
#   ./run_tests.sh              # Run all tests
#   ./run_tests.sh --quick      # Quick test (shorter stability check)
#   ./run_tests.sh --json       # Output JSON only
#   ./run_tests.sh --help       # Show help
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default settings
STABILITY_DURATION=30
JSON_OUTPUT=false
SKIP_BASELINE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --quick)
            STABILITY_DURATION=10
            shift
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --skip-baseline)
            SKIP_BASELINE=true
            shift
            ;;
        --help|-h)
            echo "SecureWave VPN Test Suite"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --quick          Run quick test (10s stability check)"
            echo "  --json           Output JSON only (no formatted summary)"
            echo "  --skip-baseline  Skip baseline measurements"
            echo "  --help, -h       Show this help message"
            echo ""
            echo "Requirements:"
            echo "  - Python 3.6+"
            echo "  - PyYAML (pip install pyyaml)"
            echo "  - System tools: ping, curl, dig, ip"
            echo ""
            echo "Results are saved to: results/latest.json"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Check Python
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}[ERROR] Python 3 is required but not installed${NC}"
    exit 1
fi

# Check required system tools
MISSING_TOOLS=()

if ! command -v ping &> /dev/null; then
    MISSING_TOOLS+=("ping")
fi

if ! command -v curl &> /dev/null; then
    MISSING_TOOLS+=("curl")
fi

if ! command -v dig &> /dev/null; then
    MISSING_TOOLS+=("dig (dnsutils)")
fi

if ! command -v ip &> /dev/null; then
    MISSING_TOOLS+=("ip (iproute2)")
fi

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    echo -e "${YELLOW}[WARNING] Some tools are missing: ${MISSING_TOOLS[*]}${NC}"
    echo "         Some tests may be skipped or produce incomplete results."
    echo ""
fi

# Check/install PyYAML
python3 -c "import yaml" 2>/dev/null || {
    echo -e "${YELLOW}[INFO] Installing PyYAML...${NC}"
    pip3 install --quiet pyyaml 2>/dev/null || pip install --quiet pyyaml
}

# Create results directory
mkdir -p results

# Build command
CMD="python3 runner.py --stability-duration $STABILITY_DURATION"

if [ "$JSON_OUTPUT" = true ]; then
    CMD="$CMD --json"
fi

if [ "$SKIP_BASELINE" = true ]; then
    CMD="$CMD --skip-baseline"
fi

# Run tests
if [ "$JSON_OUTPUT" = false ]; then
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║          SecureWave VPN Test Suite v1.0.0                 ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
fi

exec $CMD
