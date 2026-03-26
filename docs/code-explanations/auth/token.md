# `auth/token.py`

Purpose: This authentication module handles token responsibilities for SecureWave.

## Line Walkthrough

- `L1-L2`: Module or block docstring that describes the responsibility of this section.
- `L4-L11`: Implements this section of logic starting with `Design:`.
- `L13`: Imports the dependencies used later in this module, including __future__.
- `L15-L19`: Imports the dependencies used later in this module, including hmac, logging, uuid, datetime, typing.
- `L21-L24`: Imports the dependencies used later in this module, including fastapi, jose, sqlalchemy.
- `L26-L30`: Imports the dependencies used later in this module, including config, database, models, services.
- `L32-L33`: Initializes module-level state or configuration such as `logger, SETTINGS`.
- `L35-L37`: Implements this section of logic starting with `# ── Constants ──────────────────────────────────────────────────────────────────`.
- `L39-L41`: Initializes module-level variables and configuration used by later code.
- `L43-L48`: Implements this section of logic starting with `# Effective expiry — respects the hard cap in production`.
- `L50`: Initializes module-level state or configuration such as `oauth2_scheme`.
- `L53-L57`: Implements this section of logic starting with `# ── Scopes ─────────────────────────────────────────────────────────────────────`.
- `L60-L64`: Defines the `_scopes_for` function and the logic it executes.
- `L67-L69`: Implements this section of logic starting with `# ── Internal helpers ───────────────────────────────────────────────────────────`.
- `L72-L78`: Defines `_coerce_exp`. Normalise the exp claim to a naive UTC datetime.
- `L81-L84`: Implements this section of logic starting with `# ── Token creation ─────────────────────────────────────────────────────────────`.
- `L86-L106`: Implements this section of logic starting with `Claims:`.
- `L109-L112`: Implements this section of logic starting with `# ── Token validation ───────────────────────────────────────────────────────────`.
- `L114-L125`: Implements this section of logic starting with `Raises HTTP 401 on any failure (expired, tampered, wrong type, alg mismatch).`.
- `L127-L138`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L141-L159`: Defines `is_jti_revoked`. Single indexed query; constant-time at the DB layer.
- `L162-L202`: Defines `blacklist_jti`. Idempotent — safe to call multiple times for the same JTI.
- `L205-L215`: Defines `revoke_access_token`. Revoke an access token by blacklisting its JTI.
- `L218-L226`: Defines `purge_expired_blacklist`. Remove blacklist entries whose tokens have already expired. Cron-friendly.
- `L229-L236`: Implements this section of logic starting with `# ── FastAPI dependencies ───────────────────────────────────────────────────────`.
- `L238-L248`: Implements this section of logic starting with `Token source priority:`.
- `L250`: Initializes module-level state or configuration such as `payload`.
- `L252-L256`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L258-L264`: Implements this section of logic starting with `user = db.query(User).filter(User.id == int(payload["sub"])).first()`.
- `L267-L269`: Defines the `require_admin` function and the logic it executes.
- `L271`: Initializes module-level variables and configuration used by later code.
- `L273-L281`: Implements this section of logic starting with `Raises 403 (not 401) to avoid disclosing endpoint existence to unauthenticated callers`.
- `L284-L286`: Defines the `require_scope` function and the logic it executes.
- `L288-L300`: Implements this section of logic starting with `Usage:`.
- `L302`: Initializes module-level state or configuration such as `payload`.
- `L304-L305`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L307-L312`: Initializes module-level variables and configuration used by later code.
- `L314-L317`: Implements this section of logic starting with `user = db.query(User).filter(User.id == int(payload["sub"])).first()`.
- `L319`: Returns a value from the current function.
