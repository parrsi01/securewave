# GitHub state at audit time

Observed 2026-07-11 UTC through authenticated repository metadata:

- Open pull requests: 10
- Draft pull requests: 8
- Non-draft open pull requests: 2
- Pull requests with a recorded review decision: 0
- Remote branches reported: 16
- Protected branches reported: 0

Merged prerequisites:

- #26 `codex/backend-api-data-refactor`: merged as `81f8a655`.
- #27 `codex/vpn-runtime-portability-refactor`: rebased, re-certified, and
  merged as `5fc8dc7d`.

Certification PR #28's historic run `29150029857` passed its expanded matrix.
The rebased branch requires a new CI run before review; no repository setting
has been changed by this certification pass.

Older Linux runtime/evidence PRs #12 through #21 overlap newer work. The audit
does not classify them by age alone or close/delete them automatically; owner
review is required to mark superseded work and remove branches safely.

Workflow changes in this branch use immutable Action/container inputs,
read-only defaults, explicit artifact retention, isolated optional publishing,
and visible dependency/code/static/build gates. Branch protection remains an
external repository-setting blocker.
