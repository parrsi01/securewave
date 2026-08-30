# SecureWave Repository Instructions

## Source safety

- Work from the current clean worktree. Never clean, reset, overwrite, or use a
  dirty sibling worktree as a release source.
- Stage only files intentionally changed for the active request. Never use
  `git add -A` in a mixed or dirty worktree.
- Never commit credentials, private configuration, generated build trees, test
  captures, or unrelated user files.

## Save every implementation change

- After each user prompt that changes tracked source, run the relevant focused
  checks, commit the intended files, and push the current branch to GitHub.
- Report failed checks explicitly, but still preserve the requested source
  change on GitHub unless committing it would expose secrets or overwrite
  unrelated work.
- Do not create empty commits for prompts that only ask questions, request
  status, or make no tracked source change.

## Production boundary

- A Git push is not production evidence. Production updates only through the
  verified deployment workflow after its required checks pass.
- Keep backend/website deployment identity separate from downloadable client
  package version, checksum, and source provenance.
- Do not restore OpenVPN or IKEv2 to the Linux WireGuard Beta release scope.
