# Security Closeout For Linux RC

Date: 2026-05-08
Mode: verify and closeout
Execution environment: Ubuntu 24.04.4 LTS Linux VM, `aarch64`, kernel `6.8.0-111-generic`

## Executive Summary

The security/dependency remediation phase is safely closed for the current
Linux release-candidate scope.

The remediation fixed only the selected high-priority dependency issue from
`artifacts/security_dependency_audit_post_linux_rc.md`: the runtime
`python-multipart` pin was raised from `0.0.19` to `0.0.27` in the three
runtime requirement files. No runtime VPN code, protocol gating, billing state,
Flutter code, CI workflow, packaging script, or product-scope document was
changed by the remediation commit.

The validated product truth remains:

- Public v1 scope is Linux desktop only.
- WireGuard remains the primary path.
- OpenVPN remains limited to the already certified covered Linux runtime/helper
  dataplane path unless separately promoted later.
- IKEv2 is not public v1 release-visible.
- Free mode is current.
- Premium remains coming soon.

No new Linux RC blocker was found in this closeout. Live tunnel execution was
not rerun because the remediation touched only Python dependency pins and a
static dependency-pin test; no VPN runtime path changed in this pass.

## What Was Fixed

- `python-multipart==0.0.19` was replaced with `python-multipart==0.0.27` in:
  - `requirements.txt`
  - `requirements_production.txt`
  - `requirements_minimal.txt`
- `tests/unit/test_dependency_pins.py` now enforces the patched multipart pin
  across the three runtime requirement files.
- The fix closes the audit's SW-AUD-001, SW-AUD-002, and SW-AUD-003
  multipart findings by version.

## What Was Validated

Commands rerun during this closeout:

```bash
git diff --check
python3 -m pip install --dry-run -r requirements_minimal.txt
rm -rf /tmp/securewave-closeout-venv
python3 -m venv /tmp/securewave-closeout-venv
/tmp/securewave-closeout-venv/bin/python -m pip install --upgrade pip
/tmp/securewave-closeout-venv/bin/python -m pip install --dry-run -r requirements_minimal.txt
/tmp/securewave-closeout-venv/bin/python -m pip install -r requirements.txt pytest==8.2.2
/tmp/securewave-closeout-venv/bin/python -m pip check
/tmp/securewave-closeout-venv/bin/python -m pip install --dry-run -r requirements_production.txt
/tmp/securewave-closeout-venv/bin/python -c "import multipart; print(getattr(multipart, '__version__', 'unknown'))"
/tmp/securewave-closeout-venv/bin/python -m pytest tests/unit/test_dependency_pins.py tests/security/test_security.py -q
/tmp/securewave-closeout-venv/bin/python -m pytest tests/unit/test_auth.py tests/integration/test_auth.py tests/integration/test_vpn_profile.py -q
rg -n "python-multipart==0\.0\.19|python-multipart==0\.0\.27" requirements*.txt
rg -n "Form\(|File\(|UploadFile|request\.form\(|UPLOAD_DIR|UPLOAD_KEEP_FILENAME" main.py routes services tests -S
rg -n "Only WireGuard is available right now|protocol.*wireguard|OpenVPN remains limited|IKEv2 is not public|Premium coming soon|Free release candidate|Linux desktop only" routes/vpn.py docs/current_release_status.md README.md CHANGELOG.md artifacts/final_linux_phase_closeout.md
```

Results:

- `git diff --check`: passed before this closeout artifact was written and
  passed again after it was written.
- `git diff --check --no-index /dev/null artifacts/security_closeout_for_linux_rc.md`:
  no whitespace warnings for the new artifact.
- Ambient system Python rejected direct `pip install --dry-run` because Ubuntu's
  Python is PEP 668 externally managed; validation continued in an isolated
  temp venv.
- Minimal requirements dry-run selected `python-multipart==0.0.27`.
- Full `requirements.txt` installed successfully in the temp venv with
  `python-multipart==0.0.27`.
- `pip check`: passed with no broken requirements.
- Production requirements dry-run resolved successfully and would select
  `stripe-14.4.1` under the existing production range.
- Imported `multipart.__version__`: `0.0.27`.
- Dependency pin/security suite: `48 passed`.
- Auth and VPN profile regression subset: `29 passed`.
- Requirement scan found `python-multipart==0.0.27` in the three runtime
  requirement files and no remaining `0.0.19` pin in `requirements*.txt`.
- Multipart reachability scan found no current `Form`, `File`, `UploadFile`,
  `request.form()`, `UPLOAD_DIR`, or `UPLOAD_KEEP_FILENAME` backend call sites.
- Product-truth scan reconfirmed Linux desktop only, WireGuard primary,
  OpenVPN limited, IKEv2 not public v1 release-visible, Free now, and Premium
  coming soon wording in canonical release docs and backend protocol handling.

Flutter validation:

- No Flutter analyze or Flutter test was run in this closeout because the
  remediation did not touch tracked Flutter/Dart source, `pubspec.yaml`, or
  `pubspec.lock`.

Runtime validation:

- No fresh live VPN tunnel was executed in this closeout. That remains outside
  this dependency-only remediation validation and should not be claimed as
  freshly re-proven by this artifact.

## Stability And Truth Decision

Linux RC stability remains acceptable for this dependency phase.

The dependency change is narrow, resolver-compatible in minimal/runtime/
production requirement contexts, and did not change application behavior. The
current backend still rejects non-WireGuard protocol profile requests with
`Only WireGuard is available right now.`, while release-facing docs preserve
the Linux desktop, WireGuard-primary, OpenVPN-limited, IKEv2-deferred truth.

## Residual Vulnerability Meaning For Current Linux RC

The remediated multipart vulnerability is no longer meaningful for the current
Linux RC dependency set because the runtime requirement files now pin
`python-multipart==0.0.27`, and current backend code does not expose multipart
form/upload call sites.

Remaining dependency findings from the audit are still real hygiene backlog,
but they are not current Linux RC blockers based on audited reachability:

- `cryptography==44.0.1`: still deferred. Meaningful as a core dependency
  hygiene risk, but the audited vulnerable API paths were not found in the
  current Linux RC runtime path.
- `pillow==10.4.0`: still deferred. Not meaningful for current Linux RC
  exploitation based on current QR/image generation usage and no
  attacker-supplied image decoding path found.
- `python-dotenv==1.0.1`: still deferred. Not meaningful for current Linux RC
  based on current `load_dotenv()` usage and no vulnerable mutation API usage.
- `pytest==8.2.2`: still deferred. Dev/test-only and not shipped in production
  runtime.

## Remaining Deferred Risks

- Patch `cryptography` in a separate focused pass with Fernet, JWT, X25519,
  env-validation, WireGuard profile, and release-preflight coverage.
- Patch `pillow` separately with QR/image generation validation.
- Patch `python-dotenv` separately.
- Patch `pytest` separately as dev/test tooling.
- Add Linux config-file owner-only permission hardening as non-dependency work.
- Add installer archive validation and stronger artifact checksum/signature
  controls as packaging hardening.
- Add hash/constraints-based Python dependency reproducibility when release
  process scope allows it.
- Run fresh live tunnel validation only when runtime/VPN code changes or when
  cutting the final Linux RC release evidence bundle.

## Strict Change Log

### What changed

- Added this closeout artifact:
  `artifacts/security_closeout_for_linux_rc.md`.
- Revalidated the existing dependency remediation in a fresh temp venv.
- Recorded that direct ambient pip validation is blocked by the VM's
  externally managed Python policy.

### What was reused

- `artifacts/security_dependency_audit_post_linux_rc.md` as the governing
  vulnerability classification.
- `artifacts/security_dependency_remediation_pass.md` as the remediation
  implementation record.
- Existing runtime requirement structure.
- Existing backend pytest suites for dependency, security, auth, and VPN profile
  regression coverage.
- Existing release-truth docs and backend protocol handling as truth sources.

### What was intentionally left untouched

- No Python runtime code was changed.
- No FastAPI routes were changed.
- No VPN runtime code was changed.
- No Flutter/Dart files were changed.
- No CI workflow was changed.
- No packaging script was changed.
- No Dependabot branch was merged.
- No unrelated dependency was upgraded.
- No release scope was broadened.
- No OpenVPN promotion, IKEv2 public exposure, Premium-live claim, Windows,
  macOS, iOS, Android, or Azure work was introduced.

### Risks introduced

- The only introduced codebase change in this closeout is documentation.
- The prior remediation's runtime risk remains low and bounded to
  `python-multipart` resolver/runtime compatibility; the temp venv install,
  `pip check`, and targeted pytest runs passed.
- No fresh live tunnel validation was performed, so this closeout must not be
  used as new live dataplane evidence.
