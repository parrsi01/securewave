# SecureWave Privacy Policy

**Version:** 1.0
**Effective date:** February 2026
**Last reviewed:** 2026-02-19
**Contact:** privacy@securewavevpn.com

> **Status:** Ready for legal review. Placeholders marked `[PLACEHOLDER]`.

---

## 1. Introduction

SecureWave ("we," "us," or "our") operates the SecureWave VPN service, including our website, desktop applications, and mobile applications (collectively, the "Service"). This Privacy Policy explains how we collect, use, disclose, and safeguard your information.

Our core mission is to provide a private, secure internet experience. That commitment is reflected in every aspect of how we handle data.

By using the Service, you agree to this Privacy Policy. If you do not agree, do not use the Service.

---

## 2. Information We Collect

We collect only the minimum information necessary to operate the Service.

### 2.1 Account Information

| Data | Purpose |
|------|---------|
| Email address | Account identification, login, password recovery, billing communications |
| Password (bcrypt hash) | Authentication — never stored in plaintext |
| Subscription plan and status | Access control and billing |

We do not collect your name, address, or phone number. Email is the only personally identifiable identifier required.

### 2.2 Connection Metadata

To enforce subscription limits, prevent abuse, and maintain service quality:

| Data | Retention |
|------|-----------|
| Connection timestamps (connect/disconnect) | Aggregated and anonymized within 24 hours |
| Total bandwidth consumed per session | Aggregated and anonymized within 24 hours |
| VPN server region selected | Aggregated and anonymized within 24 hours |

Individual session records are purged automatically. We do not retain per-session logs beyond 24 hours.

### 2.3 Device Information

Collected to support platform-appropriate functionality:

- Operating system type and version
- SecureWave application version
- Device type (desktop, mobile, tablet)
- Language and locale settings

Device identifiers are not persistent across reinstalls and are not linked to browsing activity.

### 2.4 Support Correspondence

If you contact our support team, we retain the content of your inquiry and any attachments for up to 2 years after resolution to facilitate follow-up and quality assurance. You may request deletion of support records at any time.

### 2.5 Payment Information

Payment data is handled exclusively by our payment processors (Stripe and PayPal). See Section 5.

---

## 3. Information We Do NOT Collect — No-Logs Policy

SecureWave operates under a strict no-logs policy. We do not monitor, record, log, store, or share:

- **Browsing history** — websites, pages, or services you visit while connected
- **DNS queries** — all DNS requests are resolved by our encrypted DNS servers and are not logged
- **Originating IP address during active sessions** — authentication-phase IPs are purged after session establishment
- **Traffic content** — emails, messages, downloads, streaming activity
- **Connection activity patterns** — which services you access, what protocols you use, what data you transmit

This policy is implemented by design: even if compelled by legal process, we are technically unable to produce browsing records because they do not exist on our systems.

---

## 4. How We Use Information

Information we collect is used exclusively for:

- **Account management** — creating, maintaining, and authenticating accounts
- **Service delivery** — operating VPN infrastructure, server allocation, capacity planning
- **Billing** — processing subscription payments, managing renewal cycles, processing refunds
- **Customer support** — responding to inquiries and troubleshooting
- **Security** — detecting and preventing abuse, unauthorized access, and service disruption
- **Legal compliance** — complying with applicable laws and valid legal process

We do not sell, rent, trade, or monetize your personal data. We do not share data with advertisers, analytics providers, or data brokers.

---

## 5. Payment Information

All payment transactions are processed by Stripe and PayPal. We do not process, store, or have access to full payment card numbers.

What we receive from payment processors:
- Transaction reference ID
- Last 4 digits of card (display purposes only)
- Card type (Visa, Mastercard, etc.)
- Billing country
- Subscription status updates via webhook

Our payment processors are PCI DSS Level 1 certified. Refer to [Stripe's Privacy Policy](https://stripe.com/privacy) and [PayPal's Privacy Policy](https://www.paypal.com/privacy) for their data practices.

---

## 6. Data Security

| Measure | Implementation |
|---------|---------------|
| Encryption in transit | TLS 1.3 for all API and web traffic |
| VPN tunnel encryption | WireGuard with ChaCha20-Poly1305 or AES-256-GCM |
| Encryption at rest | AES-256 for stored account data and connection metadata |
| Credential storage | bcrypt with cost factor 12; WireGuard keys encrypted with Fernet (AES-128-CBC + HMAC-SHA256) |
| Access controls | Employee access restricted by role; all access logged and audited |
| Infrastructure | Hardened server environments; SSH key authentication; firewall rules enforced by Terraform |
| Secret management | Encryption keys stored as environment secrets; not committed to version control |
| Incident response | Documented response plan; affected users notified within 72 hours of confirmed breach |

---

## 7. Data Retention

| Category | Retention Period |
|----------|-----------------|
| Account data | Duration of active account; deleted within 30 days of account closure |
| Connection metadata | Aggregated within 24 hours; individual session records purged automatically |
| Billing records | 7 years (tax and financial compliance) |
| Support correspondence | 2 years after resolution, then deleted |
| Authentication tokens | Access tokens: 30 minutes; refresh tokens: 14 days (invalidated on logout) |

You may request early deletion of your data. We will process requests within 30 days, subject to legal retention requirements.

---

## 8. Third-Party Service Providers

We use a minimal set of third-party providers, each bound by data processing agreements:

| Provider | Role | Data shared |
|----------|------|-------------|
| Stripe | Payment processing | Email (for billing), subscription events |
| PayPal | Payment processing | Email (for billing), subscription events |
| Email delivery provider [PLACEHOLDER] | Transactional email (verification, password reset, billing notices) | Email address |
| Hetzner Cloud | Infrastructure hosting | No decrypted user data |

We do not integrate advertising networks, analytics SDKs, social media widgets, or tracking pixels into our applications.

---

## 9. Your Rights

Depending on your jurisdiction, you may have the right to:

| Right | Description |
|-------|-------------|
| Access | Request a copy of personal data we hold about you |
| Rectification | Request correction of inaccurate or incomplete data |
| Deletion | Request deletion of your personal data |
| Data portability | Request your data in a machine-readable format |
| Restrict processing | Request that we limit how we use your data |
| Object | Object to certain processing activities |
| Withdraw consent | Withdraw consent where processing is consent-based |

**EEA and UK residents** additionally have the right to lodge a complaint with their local data protection authority.

To exercise rights, contact: privacy@securewavevpn.com. We will respond within 30 days. Identity verification may be required.

---

## 10. International Data Transfers

Our infrastructure is hosted in [PLACEHOLDER — Hetzner data center regions]. If you are located in the EEA or UK and your data is transferred outside those regions, we ensure appropriate safeguards are in place, including Standard Contractual Clauses (SCCs) where applicable.

---

## 11. Children's Privacy

The Service is not directed to individuals under age 13 (or the minimum legal age in your jurisdiction). We do not knowingly collect personal data from children under 13. If we discover such data has been collected, we will delete it promptly. Parents or guardians with concerns should contact privacy@securewavevpn.com.

---

## 12. Policy Changes

When we make material changes to this Privacy Policy:
- The "Last reviewed" date above is updated
- Registered users are notified by email at least 14 days before changes take effect
- A notice is displayed within the application
- For significant changes, we may require re-acknowledgment

---

## 13. Contact

**Privacy inquiries:** privacy@securewavevpn.com
**General contact:** [Contact page](/contact)
**Response time:** 30 days

---

*This document is the authoritative source for SecureWave's privacy practices. The live version is published at https://securewavevpn.com/privacy.*
