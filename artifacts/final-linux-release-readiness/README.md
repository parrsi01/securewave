# SecureWave final Linux release-readiness certification

Date: 2026-07-12 UTC

Source: `origin/master` at `b2c69ade88a6d7d96a1478f792c39ec793888fac`

Recommendation: **not ready**

This report is evidence-only and redacted. Temporary native x86_64 and staging
resources were created in an authorized SecureWave Hetzner account and deleted
after testing. No production system was accessed, no package was published, no
manifest availability was changed, and no external load test was run.

## Gate classification

| Gate | Result | Evidence and limits |
|---|---|---|
| Master baseline and repository regression | verified | Clean isolated worktree at the revision above. Master Actions run `29165957528` passed. Repository certification passed with 381 backend tests (1 PostgreSQL concurrency test skipped without its dedicated URL), 26 Flutter tests, Flutter analysis/build, migrations, dependency audit, Bandit, Docker build, shell syntax, JavaScript syntax, release guards, and repository hygiene. ShellCheck and actionlint also passed from unprivileged local tool installs. Local Android execution was blocked by absent Java, while the exact master CI revision passed Android. |
| Public release truth | blocked | The manifest/API correctly keep the x64 `.deb` beta, but the file advertised as available at `securewave-linux-x64.tar.gz` contains an **AArch64** ELF. It is not an x86_64 build. The manifest was not changed because artifact availability changes were outside this goal's authority. |
| Native x64 `.deb` lifecycle | blocked | A clean native Ubuntu x86_64/amd64 systemd VM verified the expected SHA256 `f2718810c7dea6e2c298c159f25d904321423ab3a359c1d1428b3e824d7b4d92`, inspected and installed the GitHub artifact from run `29036573515`, and verified the app files, helper programs, enabled/active service, tmpfiles, restrictive root-owned socket, and fail-closed helper IPC. Xvfb launch remained running for the 15-second observation window with no tunnel claim. The artifact is from older commit `d0a13fbf`, package version `4.0.0+1`, and helper contract 9; current master requires contract 10. The current verifier therefore failed correctly. |
| x64 uninstall cleanup | blocked | Package-owned files, service, socket, runtime directory, WireGuard interfaces/rules, NetworkManager entries, and XFRM state were removed. Installing the package pulled in strongSwan, whose active service installed an unqualified `pref 220` lookup rule. Purging SecureWave left that dependency and rule active. Stopping strongSwan removed it and restarting strongSwan restored it. |
| Staging revision/isolation/health | verified | Disposable staging used the exact master revision. PostgreSQL, Redis, and app containers were healthy; the API was loopback-bound; readiness reported the database connected; `/version` reported staging and the exact commit. The VPN management path was restricted to the private staging network. |
| Staging user control plane | verified | A disposable operator-approved test account passed registration, verification handoff (SMTP excluded), invalid-login rejection, sign-in, authenticated profile, device registration, WireGuard profile issuance, usage endpoint, key rotation, sign-out, revoked-token rejection, subsequent sign-in and device persistence, profile revocation, and revoked-profile rejection. No credentials or profile material are retained here. |
| Protocol availability truth | verified | Linux metadata advertised WireGuard only after fresh protocol-specific evidence. OpenVPN and IKEv2 remained unavailable. |
| WireGuard live data plane | blocked | Server and authenticated management health, peer registration/removal, profile structure, and `wg0` service state were verified. A separate client tunnel was not exercised, so DNS, routes, endpoint bypass, exit-IP movement, byte-counter movement, reconnect, and disconnect cleanup are not certified. |
| OpenVPN live runtime | deferred | Not configured in the authorized staging environment and correctly not advertised. |
| IKEv2 live runtime | blocked | Not configured and correctly not advertised. The staging VPN node had zero unqualified pref-220 rules, but the x64 package lifecycle defect above violates the required cleanup gate. |
| Monitoring and alerts | blocked | Container health and logs were available. The background VPN monitor overwrote an independently authenticated healthy WireGuard observation with `unhealthy`; external alert delivery was not configured or exercised. |
| Backup/migration/recovery | verified | PostgreSQL dump, isolated restore, restored migration-version presence, cleanup, Alembic head `0006_backend_api_schema`, `alembic check`, and app restart/readiness recovery passed. |
| Rollback | blocked | The deployed image/revision and restart path were known, but an actual rollback to an earlier revision was not performed. |
| Privacy redaction/support diagnostics | verified with limits | Evidence and commands were redacted; application request logging used identifiers rather than credentials. No private key, token, account value, profile, or endpoint is committed. External support delivery was not exercised. |
| Load test | deferred | Authorization existed only in general form; no numeric target limits or abort thresholds were provided. No load traffic was generated. |
| Production deployment | not applicable | Explicitly excluded and not touched. |

## Platform and protocol status

- Linux ARM64: architecture-neutral tests and a master ARM64 Flutter release build passed locally. Prior ARM64 evidence is not x64 evidence and this run did not repeat a clean ARM64 package lifecycle.
- Linux x64: **not release-ready**. The old beta `.deb` installs but fails current contract and cleanup gates; the published x64 tar label is wrong.
- WireGuard: staging control plane and server management verified; full client data-plane certification remains blocked.
- OpenVPN: staging live proof deferred; unavailable in tested staging.
- IKEv2: staging live proof blocked/unavailable; x64 package lifecycle exposes a pref-220 cleanup defect.
- Staging: disposable control-plane and operational subset verified; monitoring, rollback, and full data-plane gates remain blocked.
- Production: not deployed or tested.
- Windows: not tested; no support claim.
- macOS: not tested; no native VPN support claim.

## Exact verification commands (redacted form)

```sh
git fetch origin
git worktree add -b agent/final-linux-release-readiness <isolated-path> origin/master
PYTHON_BIN=<venv-python> scripts/certify_repository.sh
scripts/verify_env.sh
scripts/verify_website.sh
scripts/verify_ui_v1.sh
scripts/verify_release_guards.sh
pytest -q tests/test_downloads.py tests/test_downloads_manifest.py

uname -m
dpkg --print-architecture
gh run download 29036573515 -n securewave-linux-x64-deb-evidence-1
sha256sum securewave-linux-x64.deb
dpkg-deb --info securewave-linux-x64.deb
dpkg-deb --contents securewave-linux-x64.deb
apt-get install -y ./securewave-linux-x64.deb
python scripts/linux_vpn_runtime_verifier.py --skip-build-checks --json
apt-get purge -y securewave-vpn

docker compose ps
curl --fail http://127.0.0.1:8080/api/health
curl --fail http://127.0.0.1:8080/api/ready
curl --fail http://127.0.0.1:8080/version
alembic current
alembic check
pg_dump ...
createdb <isolated-restore-db> && psql <isolated-restore-db> < <dump>
ip rule show
systemctl is-active wg-quick@wg0
```

## Required remediation before another release-readiness attempt

1. Remove or relabel the AArch64 tarball currently presented as Linux x64, under separately approved availability authority.
2. Build the x64 `.deb` from current master with helper contract 10 and repeat the clean native lifecycle verifier.
3. Prevent package installation/uninstallation from leaving the unqualified strongSwan pref-220 rule or an unwanted active dependency behind.
4. Correct and prove the VPN background health monitor against the authenticated management API.
5. Repeat authorized WireGuard client data-plane proof; configure and independently prove OpenVPN/IKEv2 only if they are intended to be offered.
6. Supply explicit load limits/abort thresholds, alert destinations, and an approved rollback revision before those gates are exercised.

Until these items are resolved, the x64 `.deb` must remain beta/build-evidence
only and SecureWave must not be described as final Linux release-ready.

## Follow-up remediation evidence

Follow-up work on this draft branch addressed several package defects without
publishing or changing availability:

- Commit `21f9ae2691cd48a9baa22d71f297df67f8c70ca9` was built by native x86_64
  Actions run `29205690262`. The workflow passed its explicit x86-64 ELF check,
  package metadata checks, manifest beta guard, and unit tests.
- Fresh artifact SHA256:
  `b8c295d351a9d577edb6f4e4c0b0a024c92acec4f1c475c333da16285251583f`.
  This is branch evidence, not a published checksum.
- strongSwan/IKEv2 components moved from mandatory dependencies to optional
  suggestions because IKEv2 is not advertised as release-ready. A newly
  recreated native x86_64 VM installed no strongSwan package and acquired no
  pref-220 rule.
- GTK, libsecret, and EGL runtime dependencies are now declared. `ldd` reported
  zero missing libraries after normal package installation.
- The contract-10 install-only verifier passed with zero failed checks. Optional
  IKEv2 tools are required only when IKEv2 is intentionally under active test;
  missing optional commands no longer crash disconnected cleanup verification.
- The service, helper payload, socket `0660 root:securewave`, tmpfiles directory
  `0750 root:securewave`, helper IPC rejection probes, and uninstall cleanup all
  passed. After purge there was no service, socket, runtime directory,
  SecureWave interface, strongSwan installation, or unqualified pref-220 rule.

The app binary loaded all declared libraries and reached Flutter/GTK window
realization under Xvfb, but aborted in `libepoxy` instead of remaining alive for
the 15-second observation window. Mesa GLX software rendering was present.
Because no native graphical desktop session was available, application launch
remains **blocked**, not verified. No tunnel claim was made.

Those remediations closed the old contract-9 and strongSwan lifecycle findings
for the tested branch artifact. At that stage the recommendation remained
**not ready** because the public x64 tarball was still an AArch64 binary and the
graphical, data-plane, monitoring, and rollback proofs had not yet run. The
continuation below supersedes those four interim statuses.

## Blocker-focused continuation

Continuation source: PR #42 commit
`6dc3fc81fb54abb6286bd68b1845fd9d4cd8a9b5`.

### Public Linux x64 tarball: blocked pending separately authorized correction

- Publication source was traced to `scripts/build_apps.sh`, which writes the
  archive into the tracked public site path
  `static/downloads/securewave-linux-x64.tar.gz`. Git history confirms that the
  current public file arrived through repository commits; no architecture
  verification protected that path.
- Native x86_64 Actions run `29207053775` rebuilt both the `.deb` and portable
  tarball from the PR branch. The workflow checks the application ELF before
  packaging and after extracting the completed tarball, and rejects anything
  other than x86-64.
- Evidence-only tarball SHA256:
  `812ec78d0161100ad0df7d3906afae32fef272a4632db60d09767b904b52ceff`.
  Manual extraction also identified `securewave_app` as an x86-64 ELF.
- The new workflow artifact was not published or copied into the public site.
  The tracked public tarball therefore remains the known AArch64 file and this
  gate remains **blocked**. Manifest availability was not changed.

### Native graphical launch: verified

- A disposable native x86_64 Ubuntu VM ran a real X.Org 21.1 graphical server
  using the Xorg dummy video driver, an Openbox window manager, a user D-Bus
  session, and Mesa llvmpipe GLX. This was not Xvfb.
- Normal `.deb` installation supplied every shared library (`ldd` reported zero
  missing entries). The SecureWave process remained alive and a visible
  `SecureWave VPN` window was observed at 1278x695 during the test window.
- Non-fatal warnings reported unavailable DRI3 acceleration and an unlockable
  headless keyring. No tunnel was started or claimed.
- No additional application change was needed. The earlier Xvfb/libepoxy abort
  remains preserved as headless-only evidence and is not used as native GUI
  proof.

### WireGuard client data plane: verified

An isolated client network namespace on authorized disposable staging obtained
a real profile from the staging backend and passed all required checks:

- authenticated peer registration and a non-zero WireGuard handshake;
- `swcert` interface creation and full-tunnel policy-table rules;
- endpoint bypass through the pre-tunnel route when applying WireGuard fwmark
  `0xca6c`;
- DNS resolution through an explicitly queried tunnel DNS resolver;
- HTTPS data-plane reachability;
- public exit IP changed from the client baseline, without retaining either
  address in evidence;
- WireGuard receive/transmit totals increased during traffic;
- `wg-quick down` removed the interface, policy rules, and table-51820 routes.

No production or non-SecureWave endpoint was targeted beyond low-volume HTTPS
and DNS proof requests.

### Staging monitoring and rollback: verified with two deferred gates

- The pre-fix behavior was reproduced after rolling the disposable app back to
  commit `f63a78c4`: deliberately unhealthy host metrics followed by a healthy
  authenticated WireGuard probe left `aggregate_status=unhealthy` while
  protocol evidence was healthy.
- The fix treats authenticated protocol reachability as an independent stronger
  runtime signal. Unit/integration tests cover recovery and compact redacted
  evidence. On the fixed image, the same sequence recovered aggregate status to
  healthy and reset consecutive failures.
- Stopping the WireGuard management API produced a false protocol result and
  unhealthy aggregate state. Restarting it produced healthy protocol evidence
  and recovered the aggregate state.
- Actual rollback to `f63a78c4` and restoration to the fixed image both passed
  container readiness. The restored image recovered the health result.
- Alert delivery is **blocked**: no authorized alert destination or delivery
  credentials were provided. Local warning logs were observed but are not
  equivalent to delivered alerts.
- Bounded load is **deferred**: no numeric target, concurrency/rate ceiling, or
  abort thresholds were supplied. No load traffic was generated.

All disposable graphical, staging app, VPN, and private-network resources were
deleted after proof. The final recommendation remains **not ready** because the
known-wrong public tarball has not been replaced, alert delivery is unproven,
and bounded-load authorization remains incomplete.

Continuation validation passed: Actions run `29207053775`, 385 Python tests
(one explicitly skipped without `SECUREWAVE_TEST_POSTGRES_URL`), Flutter
analysis, 26 Flutter tests, actionlint, ShellCheck, `git diff --check`, and the
repository secret-detection hook. No test was weakened or bypassed.
