# Development workflows

## One source branch

`master` is the only project branch. Usage recording, presentation and pending
dependency maintenance are integrated into its history. Tags identify retained
checkpoints and package candidates; they are not additional branches.

Before changing files, inspect `git status --short` and `git diff`. Keep private
configuration and local evidence outside commits. Review and stage named paths,
run the relevant checks, commit on master and push master. Avoid blanket
staging, history rewriting and deleting someone else's local artifacts.

## Review sequence

1. Read [current state](../current-state.md) and the
   [code walkthrough](../portfolio/engineering-walkthrough.md).
2. Install the pinned development requirements and Flutter dependencies.
3. Run the [software checks](testing.md) without production access.
4. For a lifecycle change, run installed acceptance on an authorized real
   account/server and retain private evidence.
5. For a release, follow the [package procedure](releasing.md).

## Common tasks

| Task | Entry point |
| --- | --- |
| Backend contracts | `make test-backend` |
| Flutter analysis and service/UI tests | `make test-flutter` |
| Native helper/wrapper checks | `make test-native` |
| Source version and document destinations | `make check` |
| Rebuild architecture PDF | `make docs` with requirements-docs installed |
| Local backend | `make backend-run` |
| Local Flutter preview | `make flutter-run` |
| ARM64 Debian candidate | `make linux-package` |
| Usage schema migration | `scripts/migrate_usage_recording.py` |
| Installed post-reboot acceptance | `scripts/securewave_post_reboot_acceptance.py` |

CI runs on master pushes. It uses disposable PostgreSQL and read-only GitHub
permissions; it does not deploy production. The
[workflow file](../../.github/workflows/ci.yml) is the executable definition.

## Repository conventions

Keep lifecycle logic in `app.dart`/services, presentation in `lib/ui`, privileged
logic in the helper, and ledger logic in `UsageMeteringService`. Keep historical
observations in `docs/archive` with their original identities. Update the
current validation record when new evidence changes the accepted result.
