#!/usr/bin/env python3
"""
Stripe Payment Security Validator
Validates webhook signatures, payment flows, and secret handling
"""

import os
import sys
import re
import json
from pathlib import Path
from typing import List, Dict, Optional, Tuple
from dataclasses import dataclass

PROJECT_ROOT = Path(__file__).parent.parent
ROUTES_DIR = PROJECT_ROOT / "routes"
SERVICES_DIR = PROJECT_ROOT / "services"

@dataclass
class StripeSecurityIssue:
    severity: str
    category: str
    file_path: str
    line_number: int
    issue: str
    recommendation: str
    code_snippet: str

class StripeSecurityValidator:
    """Validates Stripe integration security"""

    def __init__(self):
        self.issues: List[StripeSecurityIssue] = []
        self.files_checked = []

    def find_stripe_files(self) -> List[Path]:
        """Find all Stripe-related files"""
        stripe_files = []

        for directory in [ROUTES_DIR, SERVICES_DIR]:
            if directory.exists():
                for file in directory.glob("*.py"):
                    content = file.read_text(errors='ignore')
                    if 'stripe' in content.lower() or 'payment' in content.lower():
                        stripe_files.append(file)

        return stripe_files

    def check_webhook_signature_verification(self, file_path: Path, content: str):
        """Verify webhook signatures are validated"""
        lines = content.split('\n')

        # Check for webhook endpoints
        webhook_patterns = [
            r'@.*\.post\s*\(\s*[^)]*webhook',
            r'@.*\.route\s*\(\s*[^)]*webhook',
            r'def.*webhook',
            r'stripe\.webhook',
        ]

        has_webhook_endpoint = any(
            re.search(pattern, content, re.IGNORECASE)
            for pattern in webhook_patterns
        )

        if not has_webhook_endpoint:
            return

        # Check for signature verification
        sig_patterns = [
            r'stripe\.Webhook\.construct_event',
            r'construct_event\s*\(',
            r'signature.*verify',
            r'WebhookSignature',
            r'sig_header',
            r'stripe-signature',
        ]

        has_signature_check = any(
            re.search(pattern, content, re.IGNORECASE)
            for pattern in sig_patterns
        )

        if not has_signature_check:
            for i, line in enumerate(lines):
                if 'webhook' in line.lower():
                    self.issues.append(StripeSecurityIssue(
                        severity='CRITICAL',
                        category='webhook_security',
                        file_path=str(file_path.relative_to(PROJECT_ROOT)),
                        line_number=i + 1,
                        issue='Webhook endpoint without signature verification',
                        recommendation='Use stripe.Webhook.construct_event() to verify webhook signatures',
                        code_snippet=line.strip()
                    ))
                    break

    def check_secret_exposure(self, file_path: Path, content: str):
        """Check for exposed Stripe secrets"""
        lines = content.split('\n')

        # Patterns for hardcoded secrets
        secret_patterns = [
            (r'sk_live_[a-zA-Z0-9]{24,}', 'Live secret key exposed'),
            (r'sk_test_[a-zA-Z0-9]{24,}', 'Test secret key in code'),
            (r'whsec_[a-zA-Z0-9]{24,}', 'Webhook secret exposed'),
            (r'pk_live_[a-zA-Z0-9]{24,}', 'Live publishable key in backend'),
            (r'["\']sk_[a-zA-Z0-9]{10,}["\']', 'Potential secret key pattern'),
        ]

        for i, line in enumerate(lines):
            for pattern, message in secret_patterns:
                if re.search(pattern, line):
                    self.issues.append(StripeSecurityIssue(
                        severity='CRITICAL',
                        category='secret_exposure',
                        file_path=str(file_path.relative_to(PROJECT_ROOT)),
                        line_number=i + 1,
                        issue=message,
                        recommendation='Use environment variables for all secrets',
                        code_snippet=line.strip()[:100]
                    ))

    def check_idempotency(self, file_path: Path, content: str):
        """Verify idempotency keys are used"""
        lines = content.split('\n')

        # Check for payment creation without idempotency
        payment_patterns = [
            r'charges\.create',
            r'payment_intents\.create',
            r'subscriptions\.create',
            r'customers\.create',
        ]

        has_payment_creation = any(
            re.search(pattern, content)
            for pattern in payment_patterns
        )

        has_idempotency = 'idempotency_key' in content or 'Idempotency-Key' in content

        if has_payment_creation and not has_idempotency:
            for i, line in enumerate(lines):
                if any(re.search(p, line) for p in payment_patterns):
                    self.issues.append(StripeSecurityIssue(
                        severity='HIGH',
                        category='payment_safety',
                        file_path=str(file_path.relative_to(PROJECT_ROOT)),
                        line_number=i + 1,
                        issue='Payment creation without idempotency key',
                        recommendation='Add idempotency_key parameter to prevent duplicate charges',
                        code_snippet=line.strip()
                    ))
                    break

    def check_amount_validation(self, file_path: Path, content: str):
        """Verify payment amounts are validated"""
        lines = content.split('\n')

        # Look for amount handling
        amount_patterns = [
            r'amount\s*=',
            r'"amount"\s*:',
            r"'amount'\s*:",
        ]

        validation_patterns = [
            r'amount.*>\s*0',
            r'amount.*validate',
            r'max_amount',
            r'min_amount',
            r'amount.*\u003c=',
        ]

        has_amount = any(re.search(p, content) for p in amount_patterns)
        has_validation = any(re.search(p, content) for p in validation_patterns)

        if has_amount and not has_validation:
            for i, line in enumerate(lines):
                if any(re.search(p, line) for p in amount_patterns):
                    self.issues.append(StripeSecurityIssue(
                        severity='MEDIUM',
                        category='input_validation',
                        file_path=str(file_path.relative_to(PROJECT_ROOT)),
                        line_number=i + 1,
                        issue='Payment amount without validation',
                        recommendation='Validate amount is positive and within acceptable range',
                        code_snippet=line.strip()
                    ))
                    break

    def check_error_handling(self, file_path: Path, content: str):
        """Check for proper error handling in payment flows"""
        lines = content.split('\n')

        # Check for Stripe exception handling
        has_stripe_try = 'stripe.error' in content or 'StripeError' in content

        if not has_stripe_try and ('stripe' in content.lower()):
            # Find stripe calls without try/except
            for i, line in enumerate(lines):
                if 'stripe.' in line and 'import' not in line:
                    # Check if inside try block
                    context = '\n'.join(lines[max(0, i-5):i])
                    if 'try:' not in context:
                        self.issues.append(StripeSecurityIssue(
                            severity='MEDIUM',
                            category='error_handling',
                            file_path=str(file_path.relative_to(PROJECT_ROOT)),
                            line_number=i + 1,
                            issue='Stripe API call without exception handling',
                            recommendation='Wrap Stripe calls in try/except for CardError, InvalidRequestError, etc.',
                            code_snippet=line.strip()
                        ))

    def check_customer_creation(self, file_path: Path, content: str):
        """Verify customer creation logic"""
        lines = content.split('\n')

        if 'customers.create' not in content:
            return

        # Check for user association
        has_user_link = any(pattern in content for pattern in [
            'user_id',
            'user.id',
            'customer_id',
            'stripe_customer_id'
        ])

        if not has_user_link:
            for i, line in enumerate(lines):
                if 'customers.create' in line:
                    self.issues.append(StripeSecurityIssue(
                        severity='HIGH',
                        category='data_integrity',
                        file_path=str(file_path.relative_to(PROJECT_ROOT)),
                        line_number=i + 1,
                        issue='Customer creation without user association',
                        recommendation='Always link Stripe customers to application users',
                        code_snippet=line.strip()
                    ))
                    break

    def check_refund_logic(self, file_path: Path, content: str):
        """Verify refund authorization"""
        lines = content.split('\n')

        if 'refunds' not in content.lower():
            return

        # Check for authorization before refund
        auth_patterns = [
            r'current_user',
            r'admin',
            r'authorize',
            r'permission',
            r'ownership',
        ]

        has_auth = any(re.search(p, content, re.IGNORECASE) for p in auth_patterns)

        if not has_auth:
            for i, line in enumerate(lines):
                if 'refund' in line.lower():
                    self.issues.append(StripeSecurityIssue(
                        severity='HIGH',
                        category='authorization',
                        file_path=str(file_path.relative_to(PROJECT_ROOT)),
                        line_number=i + 1,
                        issue='Refund endpoint without authorization check',
                        recommendation='Verify user has permission to refund this specific charge',
                        code_snippet=line.strip()
                    ))
                    break

    def check_subscription_cancellation(self, file_path: Path, content: str):
        """Verify subscription cancellation security"""
        lines = content.split('\n')

        if 'subscriptions' not in content.lower():
            return

        # Check for ownership verification
        ownership_patterns = [
            r'user_id.*=',
            r'owner',
            r'belongs_to',
            r'current_user',
        ]

        has_ownership = any(re.search(p, content) for p in ownership_patterns)

        if not has_ownership:
            for i, line in enumerate(lines):
                if 'subscription' in line.lower() and ('cancel' in line.lower() or 'delete' in line.lower()):
                    self.issues.append(StripeSecurityIssue(
                        severity='HIGH',
                        category='authorization',
                        file_path=str(file_path.relative_to(PROJECT_ROOT)),
                        line_number=i + 1,
                        issue='Subscription modification without ownership verification',
                        recommendation='Verify requesting user owns the subscription before cancellation',
                        code_snippet=line.strip()
                    ))
                    break

    def validate_all(self):
        """Run all Stripe security validations"""
        print("=" * 60)
        print("Stripe Payment Security Validator")
        print("=" * 60)

        files = self.find_stripe_files()
        print(f"\nFound {len(files)} Stripe-related files")
        print("-" * 60)

        for file_path in files:
            print(f"  Checking: {file_path.name}")
            self.files_checked.append(str(file_path))

            try:
                content = file_path.read_text()
            except Exception as e:
                print(f"    Warning: Could not read file: {e}")
                continue

            self.check_webhook_signature_verification(file_path, content)
            self.check_secret_exposure(file_path, content)
            self.check_idempotency(file_path, content)
            self.check_amount_validation(file_path, content)
            self.check_error_handling(file_path, content)
            self.check_customer_creation(file_path, content)
            self.check_refund_logic(file_path, content)
            self.check_subscription_cancellation(file_path, content)

        return self.issues

    def generate_report(self) -> str:
        """Generate validation report"""
        critical = sum(1 for i in self.issues if i.severity == 'CRITICAL')
        high = sum(1 for i in self.issues if i.severity == 'HIGH')
        medium = sum(1 for i in self.issues if i.severity == 'MEDIUM')
        low = sum(1 for i in self.issues if i.severity == 'LOW')

        report = f"""# Stripe Payment Security Validation Report

**Generated:** {__import__('datetime').datetime.now().isoformat()}
**Files Scanned:** {len(self.files_checked)}

## Summary

| Severity | Count |
|----------|-------|
| CRITICAL | {critical} |
| HIGH | {high} |
| MEDIUM | {medium} |
| LOW | {low} |
| **TOTAL** | **{len(self.issues)}** |

## Files Scanned

"""
        for f in self.files_checked:
            report += f"- `{f}`\n"

        report += "\n## Detailed Findings\n\n"

        if not self.issues:
            report += "*No Stripe security issues detected*\n"
        else:
            for issue in sorted(self.issues, key=lambda x: ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW'].index(x.severity)):
                report += f"""### [{issue.severity}] {issue.category}

**File:** `{issue.file_path}:{issue.line_number}`

**Issue:** {issue.issue}

**Recommendation:** {issue.recommendation}

**Code:**
```python
{issue.code_snippet}
```

---

"""

        report += """## Stripe Security Checklist

### Webhook Security
- [ ] Webhook signatures verified using `stripe.Webhook.construct_event()`
- [ ] Webhook endpoint idempotent (handles duplicate events)
- [ ] Event type validated before processing
- [ ] Webhook secrets stored in environment variables

### Payment Processing
- [ ] Idempotency keys used for all payment creation
- [ ] Amounts validated (positive, within limits)
- [ ] Currency validated
- [ ] Payment methods verified for customer

### Customer Management
- [ ] Customers linked to application users
- [ ] Customer data synchronized securely
- [ ] PII handled according to PCI requirements

### Error Handling
- [ ] Stripe exceptions caught and handled
- [ ] Card errors return user-friendly messages
- [ ] InvalidRequestError logged securely
- [ ] AuthenticationError triggers alerts

### Authorization
- [ ] Users can only access their own subscriptions
- [ ] Refunds require ownership verification
- [ ] Cancellation requires ownership verification
- [ ] Admin actions require explicit authorization

### Secrets Management
- [ ] `STRIPE_SECRET_KEY` in environment only
- [ ] `STRIPE_WEBHOOK_SECRET` in environment only
- [ ] No secrets in logs or error messages
- [ ] Keys rotated regularly

"""

        return report


def main():
    validator = StripeSecurityValidator()
    validator.validate_all()

    report = validator.generate_report()

    # Save report
    report_path = PROJECT_ROOT / "STRIPE_SECURITY_REPORT.md"
    with open(report_path, 'w') as f:
        f.write(report)

    # Save JSON
    json_path = PROJECT_ROOT / "stripe_security_findings.json"
    with open(json_path, 'w') as f:
        json.dump([{
            'severity': i.severity,
            'category': i.category,
            'file_path': i.file_path,
            'line_number': i.line_number,
            'issue': i.issue,
            'recommendation': i.recommendation,
            'code_snippet': i.code_snippet
        } for i in validator.issues], f, indent=2)

    print(f"\n{'=' * 60}")
    print("Validation Complete!")
    print(f"  Report: {report_path}")
    print(f"  JSON:   {json_path}")
    print(f"  Issues: {len(validator.issues)} found")
    print("=" * 60)


if __name__ == "__main__":
    main()
