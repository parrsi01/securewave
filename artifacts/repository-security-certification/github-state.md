# GitHub state at audit time

Observed 2026-07-11 UTC through authenticated repository metadata:

- Open pull requests: 10
- Draft pull requests: 8
- Non-draft open pull requests: 2
- Pull requests with a recorded review decision: 0
- Remote branches reported: 16
- Protected branches reported: 0

Current prerequisite PRs:

- #24 `codex/full-app-baseline-and-architecture`: open draft
- #25 `codex/mobile-ui-product-refactor`: open draft
- #26 `codex/backend-api-data-refactor`: open draft; CI green at inspection
- #27 `codex/vpn-runtime-portability-refactor`: open draft; its first Python CI
  run failed because the job lacked GLib development headers for the helper
  behavior harness. Commit `0082f354` added the non-optional build dependencies;
  replacement run `29149572378` passed Repository Guards, Python, Flutter Linux,
  and Docker.

Certification PR #28 run `29150029857` passed its expanded Repository Guards,
Dependency and Code Security, 295-test Python, Flutter Linux, Flutter Android
debug compile, and Docker matrix. It remains a draft and is not merged.

Older Linux runtime/evidence PRs #12 through #21 overlap newer work. The audit
does not classify them by age alone or close/delete them automatically; owner
review is required to mark superseded work and remove branches safely.

Workflow changes in this branch use immutable Action/container inputs,
read-only defaults, explicit artifact retention, isolated optional publishing,
and visible dependency/code/static/build gates. Branch protection remains an
external repository-setting blocker.
