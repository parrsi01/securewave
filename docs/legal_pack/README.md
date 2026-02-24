# Legal Pack — SecureWave

**Version:** 4.0.0+1 | **Date:** February 2026

This directory contains production-grade legal and compliance documentation for SecureWave. These are the authoritative source documents; web-published versions in `static/` are derived from these.

---

## Contents

| File | Purpose | Status |
|------|---------|--------|
| `privacy_policy.md` | Privacy policy — data collection, retention, user rights | Ready for legal review |
| `terms_of_service.md` | Terms of service — subscription, acceptable use, liability | Ready for legal review |
| `app_store_compliance.md` | Apple App Store + Google Play compliance summary | Ready; IAP gaps noted |
| `security_whitepaper.md` | Technical security architecture — for enterprise/trust center | Internal draft; needs audit |
| `stripe_billing_transparency.md` | Billing transparency page — how Stripe and subscriptions work | Ready for publication |

---

## Placeholders Requiring Resolution

Search for `[PLACEHOLDER]` across all files before publication. Key outstanding items:

1. **Legal jurisdiction** — Terms of Service uses Delaware as governing law. Confirm this is correct for your entity structure.
2. **Email delivery provider** — Privacy policy lists `[PLACEHOLDER]` for the transactional email provider name (SendGrid, SES, etc.)
3. **IAP integration** — App Store compliance notes that in-app purchase integration may be required for App Store distribution. Confirm with Apple before submission.
4. **Trust center URL** — Security whitepaper references a trust center that does not yet exist.
5. **Test account credentials** — App Store compliance notes need live test credentials before submission.
6. **Third-party no-logs audit** — Security whitepaper explicitly flags this is not yet commissioned. Do not market "audited no-logs" until complete.

---

## Legal Review Checklist

- [ ] Privacy policy reviewed by qualified privacy counsel
- [ ] Terms of service reviewed by qualified legal counsel
- [ ] Governing law jurisdiction confirmed
- [ ] GDPR/CCPA compliance verified
- [ ] Data processing agreements in place with all third-party processors
- [ ] App Store compliance reviewed against latest App Store Review Guidelines (2026)
- [ ] Google Play compliance reviewed against latest Developer Policy Center (2026)
- [ ] Security whitepaper reviewed by security team before public release
- [ ] All `[PLACEHOLDER]` items resolved

---

## Publication

Documents in this directory should be reviewed and approved before the corresponding web pages go live. The web versions are in `static/`:

- `static/privacy.html` ← derived from `privacy_policy.md`
- `static/terms.html` ← derived from `terms_of_service.md`
- `static/billing.html` ← informed by `stripe_billing_transparency.md`
- `static/acceptable_use.html` ← subset of `terms_of_service.md` Section 5
