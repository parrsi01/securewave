# Security Dependency Remediation Pass

Date: 2026-05-08
Mode: implement and verify
Governing audit: `artifacts/security_dependency_audit_post_linux_rc.md`

## Executive Summary

This pass fixes only the highest-priority low-risk dependency issue selected
from the latest audit: `python-multipart==0.0.19` in the runtime requirement
files.

No critical-now Linux release-candidate blocker was identified in the audit.
The selected remediation covers SW-AUD-001, SW-AUD-002, and SW-AUD-003 because
all three `python-multipart` advisories are remediated by the same minimal pin
bump to `0.0.27`.

This pass does not broaden the Linux release-candidate scope, does not merge a
Dependabot branch, does not upgrade unrelated dependencies, and does not change
application runtime behavior.

## Selection From Audit

### Selected

#### SW-AUD-001 / SW-AUD-002 / SW-AUD-003: `python-multipart`

- Issue: `python-multipart==0.0.19` is pinned in `requirements.txt`,
  `requirements_production.txt`, and `requirements_minimal.txt`.
- Why it matters now: GitHub/OSV report current advisories against this
  version, including a high-severity 2026 multipart parsing denial of service
  fixed in `0.0.27`. The package is part of the Python runtime dependency
  surface.
- Smallest safe fix: update only the three canonical runtime requirement pins
  to `python-multipart==0.0.27`.
- What remains untouched: FastAPI routes, auth behavior, VPN behavior, Flutter
  code, CI workflows, packaging scripts, lockfiles, protocol visibility,
  billing state, and all unrelated dependencies.

### Not Selected In This Pass

- `cryptography==44.0.1`: important soon, but second in the audit remediation
  order and a core crypto dependency. It should be patched in a separate,
  focused pass with Fernet, JWT, X25519, env-validation, WireGuard profile, and
  release-preflight coverage.
- `pillow==10.4.0`: safe to defer for the Linux RC because no
  attacker-supplied image decoding path was found. Patch later with QR/image
  generation validation.
- `python-dotenv==1.0.1`: safe to defer because current usage is
  `load_dotenv()`, not vulnerable mutation APIs.
- `pytest==8.2.2`: dev/test-only, not shipped in production runtime.
- Linux config-file permission hardening, installer archive validation, and
  build supply-chain pinning: important hardening, but separate from this
  highest-priority dependency patch.

## Files Changed

- `requirements.txt`
- `requirements_production.txt`
- `requirements_minimal.txt`
- `tests/unit/test_dependency_pins.py`
- `artifacts/security_dependency_remediation_pass.md`

## Exact Issues Fixed

| Audit ID | Fixed by | Result |
|---|---|---|
| SW-AUD-001 | `python-multipart==0.0.27` in all runtime requirement files | Fixed |
| SW-AUD-002 | Same pin bump | Fixed |
| SW-AUD-003 | Same pin bump; current runtime was already not using the vulnerable non-default upload configuration | Fixed by version, still non-exploitable by current code evidence |

## Verification

Commands run:

```bash
python3 -m pip install --dry-run -r requirements_minimal.txt
rm -rf /tmp/securewave-remediation-venv
python3 -m venv /tmp/securewave-remediation-venv
/tmp/securewave-remediation-venv/bin/python -m pip install --upgrade pip
/tmp/securewave-remediation-venv/bin/python -m pip install -r requirements.txt pytest==8.2.2
/tmp/securewave-remediation-venv/bin/python -m pip check
/tmp/securewave-remediation-venv/bin/python -m pip install --dry-run -r requirements_production.txt
/tmp/securewave-remediation-venv/bin/python -m pytest tests/unit/test_dependency_pins.py -q
/tmp/securewave-remediation-venv/bin/python -m pytest tests/security/test_security.py -q
/tmp/securewave-remediation-venv/bin/python - <<'PY'
import multipart
print(getattr(multipart, '__version__', 'unknown'))
PY
rg -n "python-multipart==0\.0\.19|python-multipart==0\.0\.27" requirements*.txt
git diff --check
```

Results:

- `requirements_minimal.txt` dry-run resolved and selected
  `python-multipart==0.0.27`.
- Temporary validation environment installed `requirements.txt` successfully
  with `python-multipart==0.0.27`.
- `pip check` passed with no broken requirements.
- `requirements_production.txt` dry-run resolved successfully; it would install
  `stripe-14.4.1` because that file intentionally uses `stripe>=14.0.0,<15.0.0`.
- `tests/unit/test_dependency_pins.py`: `1 passed`.
- `tests/security/test_security.py`: `47 passed`.
- Installed `multipart.__version__`: `0.0.27`.
- Runtime requirement files contain `python-multipart==0.0.27`; no
  `python-multipart==0.0.19` pin remains in `requirements*.txt`.
- `git diff --check`: passed.

Validation note:

- A direct pytest attempt with the ambient Python environment failed before
  running tests because the environment lacked `fastapi`, which is imported by
  `tests/conftest.py`. Validation was then rerun in an isolated temporary venv
  outside the repository.

## Residual Security / Dependency Risks

- `cryptography==44.0.1` still has advisories identified by the audit. It is
  not fixed in this pass by design.
- `pillow==10.4.0` still has parser advisories identified by the audit. It is
  not currently reachable through attacker-supplied image decoding in the
  Linux RC path, based on the audit evidence.
- `python-dotenv==1.0.1` remains unchanged because current usage does not call
  the vulnerable mutation APIs.
- `pytest==8.2.2` remains unchanged because it is dev/test-only.
- Linux config file permission hardening and installer archive validation
  remain post-dependency hardening work.
- Requirement files still do not use hash-pinned installs; supply-chain
  reproducibility remains future hardening.

## Strict Change Log

### What changed

- Updated `python-multipart` from `0.0.19` to `0.0.27` in:
  - `requirements.txt`
  - `requirements_production.txt`
  - `requirements_minimal.txt`
- Added `tests/unit/test_dependency_pins.py` to keep the patched runtime pins
  consistent.
- Added this remediation artifact.

### What was reused

- The latest audit artifact as the governing source of truth.
- Existing runtime requirement file structure.
- Existing pytest structure under `tests/unit` and `tests/security`.
- Existing release and product-truth boundaries.

### What was intentionally left untouched

- No FastAPI route code was changed.
- No VPN runtime code was changed.
- No Flutter/Dart dependencies or lockfiles were changed.
- No CI workflow was changed.
- No packaging script was changed.
- No Dependabot branch was merged.
- No unrelated dependency was upgraded.
- No OpenVPN, IKEv2, Windows, macOS, iOS, Android, Premium, or Azure scope was
  changed.

### Risks introduced

- Runtime behavior risk is low: only a direct patch-level dependency pin changed
  for a package not currently reached by multipart endpoints.
- Dependency risk is bounded to `python-multipart` resolver compatibility; this
  was checked with minimal, runtime, and production requirement validation.
- Test maintenance risk is low: the added test is static and only enforces the
  exact patched pin across the three runtime requirement files.
