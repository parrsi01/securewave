#!/usr/bin/env bash
# SecureWave VPN - Pre-commit hook for secret detection
# Install: cp scripts/pre-commit-hook.sh .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
#
# WHAT BREAKS IF YOU TOUCH THIS:
# - This hook prevents accidental commits of secrets, API keys, and credentials
# - Disabling it risks exposing production secrets in version control
# - False positives can be bypassed with: git commit --no-verify (use sparingly)

set -euo pipefail

echo "Running secret detection pre-commit hook..."

# Get list of staged files
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM)

if [ -z "$STAGED_FILES" ]; then
    echo "No staged files to check."
    exit 0
fi

# Patterns that indicate potential secrets
# Each pattern is checked against file contents
SECRET_PATTERNS=(
    # API keys and tokens
    'AKIA[0-9A-Z]{16}'                          # AWS Access Key ID
    'sk_live_[0-9a-zA-Z]{24,}'                  # Stripe Live Secret Key
    'sk_test_[0-9a-zA-Z]{24,}'                  # Stripe Test Secret Key
    'SG\.[a-zA-Z0-9_-]{22}\.[a-zA-Z0-9_-]{43}'  # SendGrid API Key
    'xox[baprs]-[0-9a-zA-Z]{10,}'               # Slack Token

    # Private keys
    '-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----'
    '-----BEGIN PGP PRIVATE KEY BLOCK-----'

    # JWT secrets (base64 encoded, long strings that look like secrets)
    '[A-Za-z0-9_-]{40,}='                       # Base64 encoded secrets (>40 chars)

    # Database connection strings with passwords
    'postgres://[^:]+:[^@]+@'                   # PostgreSQL with password
    'mysql://[^:]+:[^@]+@'                      # MySQL with password
    'mongodb(\+srv)?://[^:]+:[^@]+@'            # MongoDB with password

    # Generic secret patterns
    'password\s*=\s*["\047][^"\047]{8,}'        # password = "..." (8+ chars)
    'secret\s*=\s*["\047][^"\047]{8,}'          # secret = "..." (8+ chars)
    'api_key\s*=\s*["\047][^"\047]{8,}'         # api_key = "..." (8+ chars)
)

# Files/paths to always skip (case insensitive matching)
SKIP_PATTERNS=(
    '\.sample$'
    '\.example$'
    '\.template$'
    '\.md$'
    'CHANGELOG'
    'LICENSE'
    '\.gitignore$'
)

FOUND_SECRETS=0

for FILE in $STAGED_FILES; do
    # Skip if file doesn't exist (deleted)
    if [ ! -f "$FILE" ]; then
        continue
    fi

    # Skip excluded patterns
    SKIP=0
    for SKIP_PATTERN in "${SKIP_PATTERNS[@]}"; do
        if echo "$FILE" | grep -qiE "$SKIP_PATTERN"; then
            SKIP=1
            break
        fi
    done

    if [ $SKIP -eq 1 ]; then
        continue
    fi

    # Check for .secrets file being staged
    if echo "$FILE" | grep -qE '\.secrets$|\.env\.local$|\.env\.production$'; then
        echo "ERROR: Attempted to commit secrets file: $FILE"
        echo "       These files should never be committed to version control."
        FOUND_SECRETS=1
        continue
    fi

    # Check file contents for secret patterns
    for PATTERN in "${SECRET_PATTERNS[@]}"; do
        if grep -qE "$PATTERN" "$FILE" 2>/dev/null; then
            # Extra validation: skip if it's in a comment or documentation context
            MATCH=$(grep -nE "$PATTERN" "$FILE" 2>/dev/null | head -1)
            if echo "$MATCH" | grep -qE '^\s*(#|//|/\*|\*|<!--)'; then
                continue
            fi
            if echo "$MATCH" | grep -qiE '(example|sample|placeholder|your[-_]?|xxx)'; then
                continue
            fi

            echo "WARNING: Potential secret found in $FILE"
            echo "         Pattern: $PATTERN"
            echo "         Line: $MATCH"
            FOUND_SECRETS=1
        fi
    done
done

if [ $FOUND_SECRETS -eq 1 ]; then
    echo ""
    echo "============================================================"
    echo "COMMIT BLOCKED: Potential secrets detected in staged files."
    echo "============================================================"
    echo ""
    echo "If these are false positives, you can:"
    echo "  1. Add the file to SKIP_PATTERNS in this script"
    echo "  2. Use 'git commit --no-verify' to bypass (use sparingly)"
    echo ""
    echo "If these are real secrets:"
    echo "  1. Remove the secrets from the file"
    echo "  2. Add the file to .gitignore"
    echo "  3. Store secrets in environment variables or a secrets manager"
    echo ""
    exit 1
fi

echo "Secret detection passed. No secrets found in staged files."
exit 0
