# Security Policy

## Reporting a vulnerability

Use GitHub private vulnerability reporting from the repository Security tab.
Do not open a public issue containing exploit details, credentials, private
keys, tokens, customer data, internal addresses, or raw operational logs.

Include the affected commit, component, minimal reproduction, expected impact,
and whether the report involved production data. Use synthetic credentials and
redacted evidence only.

## Supported code

Security fixes target the current `master` branch. Release artifacts and
platform claims remain subject to the repository release gates; a successful
source build is not proof of live VPN routing or production readiness.

## Explicit exclusions

Do not test production infrastructure, send email through configured providers,
run external load tests, alter VPN servers, or attempt privilege bypasses
without written authorization. Certificate/signing coordination and
SMTP/provider configuration are handled outside repository security reports.
