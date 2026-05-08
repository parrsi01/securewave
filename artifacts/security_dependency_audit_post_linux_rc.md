# Security Dependency Audit After Linux RC

Date: 2026-05-08
Mode: audit and prioritization only
Scope boundary: Linux desktop public release candidate, WireGuard primary, Free mode now, Premium coming soon

## Executive Summary

No confirmed security/dependency issue is currently blocking the Linux free release candidate when the canonical product truth is preserved:

- Public v1 remains Linux desktop only.
- WireGuard remains the primary release path.
- OpenVPN remains limited to the already certified covered Linux runtime/helper dataplane path unless separately promoted.
- IKEv2 is not public v1 release-visible.
- Free mode is current; Premium is coming soon.
- No release-scope broadening or Azure reintroduction is supported.

The live vulnerability surface that matters most is Python dependency hygiene, especially `python-multipart==0.0.19`. GitHub/OSV now report three advisories against that version, including a high-severity 2026 multipart header parsing denial of service fixed in `0.0.27`. The repository has a new remote Dependabot branch, `origin/dependabot/pip/python-multipart-0.0.27`, but it must not be merged as-is because it also changes release documentation context and, in branch comparison, would delete existing release artifacts. The correct later remediation is a tiny, isolated dependency pin update only, with backend regression tests and no release-scope changes.

`pillow==10.4.0`, `cryptography==44.0.1`, `python-dotenv==1.0.1`, and dev-only `pytest==8.2.2` also have current advisories. Based on repository reachability, these are non-blocking for the Linux RC:

- Pillow is used for generated QR/brand PNG output, not for decoding attacker-supplied PSD, PDF, FITS, or font/image inputs.
- cryptography is used for Fernet, X25519 fallback key generation, and JWT-related transitive support, not vulnerable SECT curve or X.509 name-constraint validation paths.
- python-dotenv is used via `load_dotenv()`, not `set_key()` or `unset_key()`.
- pytest is dev/test tooling only and is not shipped in production requirements.

Flutter/Dart dependency lock state did not surface a current OSV advisory for checked Linux-relevant direct/transitive packages. macOS, iOS, Android, Windows, and vendored WireGuard Apple surfaces are outside public v1 runtime scope and should not be used to broaden the release decision.

## Evidence Reviewed

Repository state:

- Current branch: `master`
- Upstream: `origin/master`
- `master` is aligned with `origin/master` after fetch.
- Remote dependency branches observed:
  - `origin/dependabot/pip/python-multipart-0.0.27`
  - `origin/dependabot/pip/cryptography-46.0.6`
  - `origin/dependabot/pip/python-dotenv-1.2.2`
  - `origin/dependabot/pip/pillow-12.2.0`
  - `origin/dependabot/pip/pytest-9.0.3`

Dependency and package files inspected:

- `requirements.txt`
- `requirements_production.txt`
- `requirements_minimal.txt`
- `requirements_dev.txt`
- `requirements_ml.txt`
- `securewave_app/pubspec.yaml`
- `securewave_app/pubspec.lock`
- `securewave_app/ios/Podfile`
- `securewave_app/ios/Podfile.lock`
- `securewave_app/macos/Podfile`
- `securewave_app/macos/Podfile.lock`
- `securewave_app/android/settings.gradle.kts`
- `securewave_app/android/build.gradle.kts`
- `Dockerfile`
- `Dockerfile.simple`
- `static/downloads/install-linux.sh`
- `securewave_app/scripts/build_appimage.sh`
- `securewave_app/scripts/build_deb.sh`
- `.github/workflows/ci-cd.yml`
- `.github/workflows/flutter-release.yml`
- `docs/SECRET_REMEDIATION.md`
- `docs/current_release_status.md`
- `artifacts/final_linux_phase_closeout.md`

Reachability and hardening paths inspected:

- FastAPI request parsing and middleware in `main.py`
- Auth routes in `routes/auth.py`
- VPN profile generation in `routes/vpn.py`
- WireGuard profile and QR generation in `services/wireguard_service.py`
- Linux client bridge in `securewave_app/linux/runner/my_application.cc`
- Linux packaging and installer scripts
- Dependency-related subprocess, file permission, image, dotenv, and crypto call sites

External advisory sources checked:

- GitHub Advisory Database: `GHSA-pp6c-gr5w-3c5g` / `CVE-2026-42561`
- GitHub Advisory Database: `GHSA-mj87-hwqh-73pj` / `CVE-2026-40347`
- GitHub Advisory Database: `GHSA-wp53-j4wj-2cfg` / `CVE-2026-24486`
- GitHub Advisory Database: `GHSA-r6ph-v2qm-q3c2` / `CVE-2026-26007`
- GitHub Advisory Database: `GHSA-m959-cc7f-wv43` / `CVE-2026-34073`
- GitHub Advisory Database: `GHSA-pwv6-vv43-88gr` / `CVE-2026-42311`
- GitHub Advisory Database: `GHSA-r73j-pqj5-w3x7` / `CVE-2026-42310`
- GitHub Advisory Database: `GHSA-whj4-6x5x-4v2j` / `CVE-2026-40192`
- GitHub Advisory Database: `GHSA-wjx4-4jcj-g98j` / `CVE-2026-42308`
- GitHub Advisory Database: `GHSA-cfh3-3jmp-rvhc` / `CVE-2026-25990`
- GitHub Advisory Database: `GHSA-mf9w-mj56-hr94` / `CVE-2026-28684`
- GitHub Advisory Database: `GHSA-6w46-j5rx-g56g` / `CVE-2025-71176`
- OSV batch query for selected PyPI and Pub packages

## Issue Classification Table

| ID | Surface | Current version | Advisory / signal | Severity | Release relevance | Classification | Recommended action |
|---|---|---:|---|---|---|---|---|
| SW-AUD-001 | `python-multipart` in `requirements.txt`, `requirements_production.txt`, `requirements_minimal.txt` | `0.0.19` | `GHSA-pp6c-gr5w-3c5g` / `CVE-2026-42561`, affected `<0.0.27`, patched `0.0.27` | High | Production Python dependency, but no current FastAPI `Form`, `File`, `UploadFile`, `request.form()`, or `OAuth2PasswordRequestForm` route was found | Important soon but not blocking Linux RC | Later perform a minimal pin bump to `0.0.27` in all three requirement files. Do not merge the remote Dependabot branch as-is. Run backend tests and smoke tests after the isolated bump. |
| SW-AUD-002 | `python-multipart` | `0.0.19` | `GHSA-mj87-hwqh-73pj` / `CVE-2026-40347`, affected `<0.0.26`, patched `0.0.26` | Moderate | Same reachability as SW-AUD-001 | Important soon but not blocking Linux RC | Covered by the same isolated bump to `0.0.27`. |
| SW-AUD-003 | `python-multipart` | `0.0.19` | `GHSA-wp53-j4wj-2cfg` / `CVE-2026-24486`, affected `<0.0.22`, patched `0.0.22` | High | False-positive for current app configuration: no use of `UPLOAD_DIR` plus `UPLOAD_KEEP_FILENAME=True`; no multipart upload endpoint found | False positive for current canonical runtime, but fixed by same future bump | Record as not currently exploitable. Upgrade with SW-AUD-001 when dependency patching is authorized. |
| SW-AUD-004 | `pillow` in Python runtime requirements | `10.4.0` | Multiple 2026 Pillow advisories fixed by `12.2.0`, including PSD OOB write, PDF DoS, FITS decompression bomb, and font integer overflow | High / Moderate | Installed in production, but current code generates PNG QR codes and brand assets; no attacker-supplied `Image.open()` path found in backend release runtime | Safe to defer from Linux RC; important soon for dependency hygiene | Later test and bump Pillow in isolation. Keep image decoding of untrusted uploads out of scope unless explicitly designed with format allowlists. |
| SW-AUD-005 | `cryptography` in Python runtime requirements | `44.0.1` | `GHSA-r6ph-v2qm-q3c2`, affected `<=46.0.4`, patched `46.0.5`; `GHSA-m959-cc7f-wv43`, affected `<46.0.6`, patched `46.0.6` | High / Low | Installed in production, but current use is Fernet, X25519 fallback, key validation, and JWT ecosystem support. No SECT curves, attacker-supplied public key loaders, or X.509 name-constraint validation path found | Important soon but not blocking Linux RC | Later perform a focused cryptography bump to `46.0.6`, with auth, key-generation, env-validation, and WireGuard profile tests. Do not merge the current remote branch because it reintroduces Azure-era dependency/context changes. |
| SW-AUD-006 | `python-dotenv` in Python requirements | `1.0.1` | `GHSA-mf9w-mj56-hr94`, affected `<1.2.2`, patched `1.2.2` | Moderate | Code uses `load_dotenv()` only; no `set_key()` or `unset_key()` call sites found | Safe to defer from Linux RC | Later bump to `1.2.2` in a small patch. Keep production config write paths outside python-dotenv mutation APIs. |
| SW-AUD-007 | `pytest` in dev requirements | `8.2.2` | `GHSA-6w46-j5rx-g56g`, affected `<9.0.3`, patched `9.0.3` | Moderate | Dev/test only; not in production requirements or Linux runtime | Safe to defer | Later bump pytest separately and expect possible test-runner compatibility work. Not a release blocker. |
| SW-AUD-008 | Flutter/Dart dependency set | Locked in `securewave_app/pubspec.lock` | OSV query for checked Linux-relevant Pub packages returned no current advisory hits | None found | Linux desktop app dependency lock exists and is release-relevant | No issue found in current check | Keep `pubspec.lock` committed. Avoid broad `flutter pub upgrade` during RC stabilization. |
| SW-AUD-009 | macOS/iOS CocoaPods and vendored WireGuard Apple tree | Pod locks and vendored source present | Platform and vendored-third-party scan noise | Mixed / not assessed for public v1 | macOS/iOS are not public v1 runtime targets | Safe to defer / non-canonical noise for Linux RC | Do not treat Apple vendored findings as Linux RC blockers. Run a separate Apple release audit before promoting Apple platforms. |
| SW-AUD-010 | Android Gradle / WireGuard Android dependency | `com.wireguard.android:tunnel:1.0.20260102` | No Linux RC exposure | Not Linux RC | Android VPN runtime is outside public v1 | Safe to defer | Audit only if Android is selected as a later release track. |
| SW-AUD-011 | Remote Dependabot branches | N/A | Branch diffs include dependency bumps but also stale release-context/Azure-era changes on several branches | Release integrity risk | Directly relevant to preserving Linux RC truth | Important soon, not a vulnerability | Do not merge remote Dependabot branches as-is. Recreate minimal dependency-only patches from `master` when patching is authorized. |
| SW-AUD-012 | Linux client WireGuard config file write | N/A | `my_application.cc` writes `~/.config/securewave/securewave.conf` via `g_file_set_contents`; parent dir is `0700`, but file mode is not explicitly forced to `0600` in the tracked source | Hardening | Linux runtime path | Important soon but not a dependency blocker | Later add explicit owner-only chmod after config write and test it. Directory `0700` limits practical exposure, so this does not block the current dependency audit. |
| SW-AUD-013 | Linux installer tar extraction | N/A | `static/downloads/install-linux.sh` extracts a local tarball as root without archive path validation | Packaging hardening | Linux installer path | Important soon but not blocking current RC if artifacts are distributed with checksums and local tarball is trusted | Later harden installer extraction with archive path validation and checksum/signature verification. Do not change during this audit. |
| SW-AUD-014 | Docker and CI package install reproducibility | N/A | Runtime requirements are pinned, but pip hashes are not enforced; release workflow installs `appimage-builder` without a pinned version | Supply-chain hardening | Backend/build pipeline, not Linux desktop runtime behavior | Important soon | Later add a constraints/hash strategy and pin release build tools deliberately. Do not upgrade blindly during RC. |
| SW-AUD-015 | Historical secrets | N/A | `docs/SECRET_REMEDIATION.md` records prior git-history findings | Operational security | Not a new dependency issue | Already documented, not blocking this audit | Continue treating historical material as compromised until rotated. No history rewrite performed. |

## Critical Now For Linux Release Candidate

None confirmed.

No issue reviewed in this audit currently requires blocking or broadening the Linux free release candidate, provided the current product truth remains unchanged and no new upload/form, image-decoding, Apple/mobile, Android, IKEv2, Azure, or paid-production scope is introduced.

## Important Soon But Not Blocking Current Linux RC

1. `python-multipart` should be patched first once code changes are authorized.
   - Target version: `0.0.27`.
   - Files: `requirements.txt`, `requirements_production.txt`, `requirements_minimal.txt`.
   - Rationale: real high-severity remote DoS advisory exists, direct production dependency exists, and the update appears low-risk if isolated.
   - Constraint: do not merge `origin/dependabot/pip/python-multipart-0.0.27` directly.

2. `cryptography` should be patched next.
   - Target version: `46.0.6`.
   - Files: `requirements.txt`, `requirements_production.txt`.
   - Rationale: core crypto library with real advisories, even though current vulnerable APIs are not reached.
   - Constraint: test Fernet validation, JWT flows, X25519 fallback, WireGuard profile generation, and release preflight.

3. `pillow` should be patched after QR/image generation tests are ready.
   - Target version indicated by Dependabot: `12.2.0`.
   - Files: `requirements.txt`, `requirements_production.txt`.
   - Rationale: multiple real image parser advisories, but current release path generates images rather than decoding untrusted input.

4. Linux client config permissions should be hardened.
   - Add explicit `0600` permissions after writing `securewave.conf`.
   - This is not a dependency patch and should be handled separately.

5. Packaging supply-chain controls should be improved.
   - Add artifact checksum/signature verification and archive path validation.
   - Pin build-time tools such as `appimage-builder`.
   - Consider pip hash checking or an approved lock/constraints workflow.

## Safe To Defer

- `python-dotenv==1.0.1` because only `load_dotenv()` is used, not vulnerable mutation APIs.
- `pytest==8.2.2` because it is dev/test only.
- Flutter/Dart dependency upgrade churn because OSV did not report checked Pub advisories for the Linux-relevant locked packages.
- macOS/iOS CocoaPods and vendored WireGuard Apple scan noise because Apple platforms are outside public v1 runtime scope.
- Android Gradle/WireGuard Android dependency work because Android is outside public v1 runtime scope.
- OpenVPN expansion, IKEv2 hardening, and multi-platform runtime work because those are post-v1 promotion tracks.

## False Positive / Non-Canonical / Vendored-Third-Party Noise

- `python-multipart` arbitrary file write via non-default `UPLOAD_DIR` plus `UPLOAD_KEEP_FILENAME=True`: no matching project configuration or multipart upload endpoint was found.
- Pillow parser advisories for PSD/PDF/FITS/font processing: no backend path was found that decodes attacker-supplied image files with Pillow in the Linux RC runtime.
- Vendored `securewave_app/ios/ThirdParty/wireguard-apple/**`: not canonical Linux RC runtime code. Treat findings there as Apple-platform backlog, not Linux release blockers.
- Remote Dependabot branches carrying Azure-era or stale context: treat the dependency version target as a signal only, not the branch as an acceptable change set.

## Do-Not-Touch Boundaries

Do not change any of the following as part of vulnerability closure unless separately authorized:

- Do not broaden public release scope beyond Linux desktop.
- Do not expose IKEv2 in public v1.
- Do not promote OpenVPN beyond the already certified covered Linux runtime/helper dataplane path.
- Do not reintroduce Azure files, Azure dependencies, Azure docs, Azure CI wording, or Azure deployment assumptions.
- Do not convert Free mode into paid-live messaging.
- Do not claim Premium is live before billing and production account flows are separately validated.
- Do not perform broad dependency upgrades.
- Do not merge stale Dependabot branches directly.
- Do not modify platform runtime files for macOS, iOS, Android, or Windows as part of the Linux RC dependency fix.
- Do not rewrite git history during dependency closure.
- Do not change VPN protocol behavior or packaging truth while patching Python dependencies.

## Recommended Remediation Order

1. Create a dependency-only branch from current `master`.
2. Patch `python-multipart` to `0.0.27` in only:
   - `requirements.txt`
   - `requirements_production.txt`
   - `requirements_minimal.txt`
3. Run:
   - `python -m pip install -r requirements_dev.txt`
   - `pytest tests -q`
   - `bash scripts/verify_release_guards.sh`
   - `git diff --check`
4. Patch `cryptography` to `46.0.6` in a separate commit/PR.
5. Run auth, env validation, WireGuard profile generation, and release preflight tests.
6. Patch `pillow` to `12.2.0` in a separate commit/PR.
7. Run QR generation tests and any brand asset generation checks.
8. Patch `python-dotenv` to `1.2.2` separately.
9. Patch `pytest` to `9.0.3` separately, accepting that dev tooling may require small test harness adjustments.
10. After dependency closure, harden Linux config file permissions and installer/archive verification as separate non-dependency work.

## Validation

Commands run during this audit:

```bash
git fetch --all --prune
git status --short --branch
git log --oneline --decorate --left-right --cherry-pick master...origin/master
rg --files -g 'requirements*.txt' -g 'pubspec.yaml' -g 'pubspec.lock' -g 'Podfile*' -g '*.gradle.kts' -g 'Dockerfile*' -g '*.sh' -g '*.yml' -g '*.yaml'
rg -n 'UploadFile|File\(|Form\(|multipart|request\.form\(|UPLOAD_DIR|UPLOAD_KEEP_FILENAME|PIL|Image\.open|ImageMath|cryptography|subprocess|wg-quick|openvpn|ikev2'
rg -n 'from dotenv|load_dotenv|set_key|unset_key'
rg -n 'Image\.open|ImageMath|PIL|qrcode\.make|QRCode'
rg -n 'SECT|EllipticCurve|ECDH|ECDSA|load_pem_public_key|load_der_public_key|public_key_from_numbers|x509|Fernet|X25519|jwt'
```

OSV batch query summary:

- PyPI `python-multipart==0.0.19`: 3 advisories.
- PyPI `cryptography==44.0.1`: 2 advisories.
- PyPI `pillow==10.4.0`: 5 advisories.
- PyPI `python-dotenv==1.0.1`: 1 advisory.
- PyPI `pytest==8.2.2`: 1 advisory.
- Checked PyPI `fastapi`, `uvicorn`, `gunicorn`, `httpx`, `jinja2`, `PyYAML`, `xgboost`, `numpy`, `scikit-learn`: no advisory returned for the pinned version in the OSV query.
- Checked Pub `dio`, `flutter_secure_storage`, `archive`, `flutter_svg`, `http`, `image`, `xml`, `connectivity_plus`: no advisory returned for the locked version in the OSV query.

Final validation after this artifact was written:

```bash
git diff --check
git diff --check --no-index /dev/null artifacts/security_dependency_audit_post_linux_rc.md
```

## Strict Change Log

### What changed

- Added this audit artifact: `artifacts/security_dependency_audit_post_linux_rc.md`.
- Fetched remote GitHub updates and recorded the new/current Dependabot dependency signals.
- Classified current dependency advisories by Linux RC reachability and release relevance.

### What was reused

- Existing canonical Linux RC truth from `README.md`, `docs/current_release_status.md`, and `artifacts/final_linux_phase_closeout.md`.
- Existing dependency pins and lockfiles.
- Existing CI/release guardrails.
- Existing secret-remediation documentation.
- Existing Linux WireGuard runtime evidence and `wg-quick` path.

### What was intentionally left untouched

- Application code.
- Python dependency files.
- Flutter/Dart dependency files.
- Lockfiles.
- CI workflows.
- Packaging scripts.
- VPN runtime code.
- Billing and Premium behavior.
- OpenVPN/IKEv2 visibility.
- macOS/iOS/Android/Windows runtime surfaces.
- Remote Dependabot branches.
- Historical git secret-remediation state.

### Risks introduced

- No runtime risk; this is documentation-only.
- No dependency risk; no package versions were changed.
- No release-scope risk; the artifact explicitly preserves Linux-only public v1 boundaries.
- Process risk remains if future remediation merges stale Dependabot branches directly instead of recreating minimal dependency-only patches.
