# SecureWave Coding Agent Contract

## Operating rule

Work from repository evidence. Do not invent files, routes, APIs, commands,
configuration values, test results, deployment state, or model behavior.

## Before changing code

1. Read the relevant files and nearby tests.
2. Run `git status --short --branch`.
3. Identify the exact source of truth for the requested behavior.
4. State unknowns explicitly. Do not fill missing values with guesses.

## Editing rules

- Keep changes narrowly scoped to the request.
- Preserve existing behavior outside the requested change.
- Use `rg` and `rg --files` for repository searches.
- Use `apply_patch` for manual edits.
- Do not overwrite, reset, or discard existing user changes.
- Do not use destructive Git commands.
- Do not add placeholder code, fake data, invented dependencies, or
  unverified endpoint names.
- For security-sensitive or production behavior, fail closed.

## Verification rules

After editing:

1. Run the smallest relevant test or check.
2. Run syntax, formatting, and contract checks appropriate to the files changed.
3. Run `git diff --check`.
4. Inspect the final diff for unrelated changes.
5. Report exact commands and whether each passed, failed, or was not run.

Never say "tests pass", "deployed", "live", "fixed", or "verified" unless a
command or tool result in the current task proves that statement.

## External systems and deployment

- Local source changes are not a deployment.
- Do not infer a production host, image, registry, credentials, SSH identity,
  environment file, or CI runner.
- Do not print or request secret values.
- Do not deploy from an uncommitted or unverified tree.
- Before any production mutation, verify the authorized target, immutable image,
  required environment, and explicit deployment confirmation.
- If a required external value or access path is missing, stop and report the
  exact blocker. Do not bypass a fail-closed deployment guard.
- After deployment, verify the public URL and the behavior that was changed.

## Response format

End implementation tasks with:

- Changed: files and behavior changed.
- Verified: commands and observed results.
- Blocked: only external dependencies or checks that genuinely remain.

Keep facts, assumptions, and recommendations clearly separate.
