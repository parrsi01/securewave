# Codex Plan — Land Demo Work on `master` + Release Hygiene

**Why:** the branch model (README) is `master` = backend/docs/infra/release
truth, `flutter` = app design branch. The demo hardening landed on `flutter`
(commit `3481c3e`), but several pieces are repo-level, not app-UI: they belong on
`master` so release truth and ops tooling stay correct.

## What needs to reach `master`
| Artifact | Belongs on master? | Reason |
|----------|--------------------|--------|
| `scripts/demo_preflight.sh` | **Yes** | ops/release tooling |
| `docs/DEMO_RUNBOOK.md`, `docs/CODEX_*` plans | **Yes** | docs/release truth |
| Presentation Mode app code (`lib/...`, `linux/...`) | Per branch model | app UI normally lives on `flutter`; mirror to master only if master must build the same app |
| `.env.template` additions (if T7 done) | **Yes** | config truth |

## Tasks
1. **Decide app-code home.** Confirm whether `master` is expected to build the
   Flutter app (some repos keep app only on `flutter`). If yes, merge/cherry-pick
   the Presentation Mode commit to `master`; if no, only port scripts + docs.
2. **Port ops/docs.** Cherry-pick the script + doc commits onto `master` (or open
   a `flutter → master` PR limited to those paths). Keep history clean; don't drag
   unrelated app churn if the branch model forbids it.
3. **Update release truth.** Reflect Presentation Mode in
   `docs/current_release_status.md` (a new opt-in demo flag; default behavior
   unchanged; not a protocol-readiness change) and bump `CHANGELOG.md`.
   Do NOT alter the v1 scope statement or protocol-visibility claims.
4. **Tag a demo checkpoint.** After the dry run passes, tag (e.g.
   `demo-ready-2026-06-28`) on the verified commit so the demo can be reproduced.
5. **Guardrails.** Re-run `scripts/release_preflight.sh` / `devops_preflight.sh`
   on `master` post-merge; confirm secret-scan + analyze gates pass.

## Acceptance
- `scripts/demo_preflight.sh`, runbook, and plan docs exist on `master`.
- `current_release_status.md` + `CHANGELOG.md` note the opt-in Presentation Mode
  without overstating readiness.
- A reproducible tag points at the verified demo commit.
- Preflight/secret-scan gates green on `master`.

## Guard
Honor the project rule: do not change website or Flutter UI scope on `master`
beyond what's needed to carry the opt-in flag; keep protocol-visibility and v1
release claims untouched.
