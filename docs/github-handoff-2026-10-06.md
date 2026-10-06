# GitHub save checkpoint — 2026-10-06

The current source branches, remaining local checkpoint history, reboot-test
automation, and release candidate assets have been saved to
[`parrsi01/securewave`](https://github.com/parrsi01/securewave). Branches remain
separate for review. The primary checkout and its local-only files were
preserved.

## Current work

| Work | GitHub location | Identity |
| --- | --- | --- |
| Published source baseline | `master` | `9e4f7587a37c9a97d2c9fcc393654b07dcbcf412` |
| Usage recording and installed candidate | `codex/usage-recording-20261005`, [draft PR 109](https://github.com/parrsi01/securewave/pull/109) | Installed application source `c90dc03f5ccbab5fffb2fcaefedc72ea36e34527` |
| Reboot automation and status | `codex/usage-recording-20261005` | Checkpoint commit `3f0ffa28cd5d1df204990e73ce6a0c5bf8cfa6a9`; this handoff record follows it |
| Separate UI preview | `codex/flutter-ui-redesign` | `0e72924ea61924b34b969407fe05d5020dc4b4f7` |

The current branches were pushed and their advertised GitHub heads verified.
The saved automation, post-reboot checkpoint and historical release-note
snapshot were also verified against GitHub file blob identities.

The GitHub `v4.0.0+12` draft retains its exact candidate source and three
uploaded assets: the ARM64 Debian package, portable checksum and source-SHA
provenance file. The 15,115,608-byte package digest is
`0947842068f41ee9c5f787cffe6776d7e01b432b8d08db2ba142f43254384f98`.
The draft release and PR descriptions now record the post-reboot checkpoint.

## Historical checkpoint preservation

Six local checkpoint tags were absent from GitHub. Their original tag
objects and reachable history are saved under the following remote archive
refs. The original local tags are preserved.

| Original local tag | Saved GitHub tag |
| --- | --- |
| `checkpoint-vpn-protocols-2026-02-28` | `archive/local-tag-checkpoint-vpn-protocols-2026-02-28` |
| `pre-ui-vpn-fix-2026-02-28` | `archive/local-tag-pre-ui-vpn-fix-2026-02-28` |
| `rescue_pre_cleanup_20260226_231103` | `archive/local-tag-rescue_pre_cleanup_20260226_231103` |
| `ui-checkpoint-purple-2026-03-30` | `archive/local-tag-ui-checkpoint-purple-2026-03-30` |
| `v1.0.0-non-apple` | `archive/local-tag-v1.0.0-non-apple` |
| `v1.0.0-rc1` | `archive/local-tag-v1.0.0-rc1` |

The two original `v1` names match historical automatic release workflows.
The archive names preserve the snapshots without matching those release
triggers. A targeted scan reviewed the 17 previously unadvertised commits
and their new blobs. Matches were scanner definitions, shell expansions,
field names and test fixtures. Two historical packages included an app
configuration asset with endpoint/reset-setting names; it contained no
nonempty credential settings or high-confidence secret match. This was a
publish-safety check, not a security audit or validation of those old releases.

The pre-existing local September release note is also saved as an explicitly
[historical snapshot](archive/linux-release-status-2026-09-29.md).

## Local data and remaining acceptance

Private account storage, keys, credentials, raw runtime evidence, historical
test artifacts, generated Android/iOS files, and local settings remain
outside this Git handoff. The primary checkout's pre-existing untracked
files were left in place; no reset, clean, stash or merge was performed.

The portable GUI harness passed Python syntax validation and its real
installed-app baseline operation. Diff checks and the commit secret hook
passed. The app's saved session has expired. Post-reboot Connect, traffic,
Reconnect, final usage persistence and clean Disconnect still await sign-in;
the 4.0.0+12 release remains a draft. See the
[post-reboot checkpoint](releases/4.0.0+12-post-reboot.md).
