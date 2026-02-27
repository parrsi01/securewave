# SecureWave VPN — Project Rules

## RISK TIERS & REQUIRED GATES

| Risk | Examples | Gate |
|------|----------|------|
| LOW | cosmetic, additive, test-only | just do it |
| MEDIUM | logic change, single service/file | state intent, then do it |
| HIGH | auth, state machine, native bridge (my_application.cc), cross-cutting | show diff, get explicit approval |

**Default: assume LOW unless evidence of MEDIUM/HIGH.**
Do not ask for scope contracts on LOW risk tasks. Read → fix → done.

---

## HARD RULES (all risks)

- No auto-commit, no auto-push.
- No refactors unless `MODE: REFACTOR` declared.
- No files touched outside stated scope.
- No speculative improvements — fix only what was asked.
- `flutter analyze` must pass (0 errors) before any commit.

---

## OUTPUT

- Dense, direct. No architecture restatement. No padding.
- For MEDIUM: one-line intent before editing.
- For HIGH: show unified diff, wait for approval.
- For LOW: just make the change.

---

## TOKEN DISCIPLINE

- Read only files needed for the task.
- One task per prompt — "fix X" is not license to improve Y/Z.
- No verbose explanations unless asked.
- Medium reasoning default. High only for security modeling or deep arch ambiguity.

---

## SECUREWAVE SPECIFICS

- VPN state machine lives in `lib/core/state/vpn_state.dart` — HIGH risk, always gate.
- Native bridge: `linux/runner/my_application.cc` — HIGH risk.
- Auth flow: `lib/features/auth/` — HIGH risk.
- UI/theme changes: LOW risk unless touching state wiring.
- Backend routes: `routes/` — MEDIUM risk.
