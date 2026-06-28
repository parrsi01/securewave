# Codex Plan — Dependabot Remediation (42 alerts on default branch)

**Trigger:** the `flutter` push surfaced GitHub's standing Dependabot warning —
**42 vulnerabilities on the default branch (`master`)**. The branch push was
clean; these alerts are repo-wide security debt, not a push blocker.
**Branch for fixes:** `master` (alerts track the default branch). Do this as its
own PR, separate from demo work.

## Ground truth (verified)
- No `.github/dependabot.yml` exists → alerts are on, but there is no update
  automation and no grouping.
- Ecosystems in repo: **pip** (`requirements.txt`, `requirements_production.txt`,
  `requirements_dev.txt`, `requirements_minimal.txt`, `requirements_ml.txt`),
  **Flutter pub** (`securewave_app/pubspec.lock`), **GitHub Actions**
  (`.github/workflows/*.yml`). No top-level npm lockfile.
- `gh` CLI is authenticated (account `parrsi01`) → alerts are queryable directly.

## Tasks
1. **Triage — get the real list (don't guess).**
   ```bash
   gh api -H "Accept: application/vnd.github+json" \
     "/repos/{owner}/{repo}/dependabot/alerts?state=open&per_page=100" --paginate \
     | jq -r '.[] | [.security_advisory.severity, .dependency.package.ecosystem,
              .dependency.package.name, .security_vulnerability.vulnerable_version_range,
              .security_advisory.ghsa_id] | @tsv' | sort | uniq -c | sort -rn
   ```
   Produce a table grouped by severity × ecosystem × package. Most are likely
   transitive pip deps.
2. **Enable Dependabot config.** Add `.github/dependabot.yml` with weekly updates
   + grouping for `pip` (each requirements file dir), `github-actions`, and
   `pub` (`/securewave_app`). This prevents the backlog from re-accumulating.
3. **Fix pip (highest count first).** For each vulnerable package, bump the pin in
   the requirements file(s) to the first patched version. Validate the resolve
   with `pip install -r requirements.txt` in a clean venv and run `pip-audit`
   (add to `requirements_dev.txt`) to confirm 0 known vulns. Watch the pinned
   crypto/auth stack (`cryptography`, `python-jose`, `bcrypt`, `passlib`,
   `pyasn1`) — these are security-critical; bump deliberately and re-run the auth
   tests.
4. **Fix Flutter pub.** `cd securewave_app && flutter pub outdated` and
   `flutter pub upgrade` for flagged packages; keep within `pubspec.yaml`
   constraints; re-run `flutter analyze` + `flutter test`.
5. **Fix GitHub Actions.** Pin third-party actions in `.github/workflows/*.yml`
   to current major (or SHA) for any flagged action.
6. **Regression gate.** `pytest`, `flutter analyze`, `flutter test`, and a backend
   import smoke (`python -c "import main"`) must all pass after bumps. Run
   `scripts/devops_preflight.sh` if it covers deps.

## Acceptance
- `gh api .../dependabot/alerts?state=open` count drops to 0 (or every remaining
  alert is explicitly risk-accepted with a documented reason).
- `pip-audit` clean on `requirements.txt` + `requirements_production.txt`.
- `.github/dependabot.yml` present and valid.
- All test/analyze gates green; backend imports; app builds.
- Changes land on `master` via a dedicated "deps: remediate Dependabot alerts" PR.

## Sequencing
Independent of the demo. Recommended order: Critical/High pip → Actions → pub →
Moderate/Low. Batch by ecosystem to keep each PR reviewable. Do not mix dep bumps
with feature commits.
