# `auth/refresh_tokens.py`

Purpose: This authentication module handles refresh tokens responsibilities for SecureWave.

## Line Walkthrough

- `L1-L2`: Module or block docstring that describes the responsibility of this section.
- `L4-L13`: Implements this section of logic starting with `Design:`.
- `L15`: Imports the dependencies used later in this module, including __future__.
- `L17-L20`: Imports the dependencies used later in this module, including logging, uuid, datetime, typing.
- `L22-L24`: Imports the dependencies used later in this module, including fastapi, jose, sqlalchemy.
- `L26-L34`: Implements this section of logic starting with `from auth.token import ALGORITHM, blacklist_jti, _utcnow, _coerce_exp`.
- `L36-L37`: Initializes module-level state or configuration such as `logger, SETTINGS`.
- `L39-L41`: Initializes module-level state or configuration such as `_ALLOWED_ALGORITHMS`.
- `L44-L53`: Implements this section of logic starting with `# ── Creation ───────────────────────────────────────────────────────────────────`.
- `L55-L60`: Implements this section of logic starting with `The token string is returned for the caller to set as HttpOnly cookie.`.
- `L62-L70`: Initializes module-level state or configuration such as `payload, token`.
- `L72-L91`: Implements this section of logic starting with `db.add(`.
- `L94-L103`: Implements this section of logic starting with `# ── Validation ─────────────────────────────────────────────────────────────────`.
- `L105-L109`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L112-L125`: Defines `_load_session`. Load the DB session record for a JTI, enforcing all validity checks.
- `L127`: Implements this section of logic starting with `session = db.query(AuthRefreshToken).filter(AuthRefreshToken.token_jti == jti).first()`.
- `L129-L130`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L132-L139`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L141-L142`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L144-L153`: Implements this section of logic starting with `register_refresh_session(`.
- `L155`: Returns a value from the current function.
- `L158-L160`: Defines the `_invalidate_replacement_chain` function and the logic it executes.
- `L162-L168`: Implements this section of logic starting with `This is the theft-detection response: if a previously rotated token is`.
- `L170-L185`: Loops over a collection to apply the same work to each item.
- `L187-L205`: Initializes module-level state or configuration such as `now`.
- `L207-L211`: Implements this section of logic starting with `db.commit()`.
- `L214-L223`: Implements this section of logic starting with `# ── Rotation ───────────────────────────────────────────────────────────────────`.
- `L225`: Implements this section of logic starting with `Returns (new_access_token_str, new_refresh_token_str).`.
- `L227-L229`: Implements this section of logic starting with `Callers MUST set the returned tokens via HttpOnly cookies — not in JSON.`.
- `L231-L233`: Initializes module-level state or configuration such as `payload, old_jti, session`.
- `L235-L237`: Implements this section of logic starting with `user = db.query(User).filter(User.id == session.user_id).first()`.
- `L239-L246`: Implements this section of logic starting with `# Mint new tokens`.
- `L248-L250`: Implements this section of logic starting with `# Revoke old session (record replacement linkage for chain invalidation)`.
- `L252-L269`: Initializes module-level state or configuration such as `session.revoked_at, session.replaced_by_jti, jti, token_type, expires_at, user_id`.
- `L271`: Returns a value from the current function.
- `L274-L297`: Implements this section of logic starting with `# ── Logout ─────────────────────────────────────────────────────────────────────`.
- `L300-L302`: Defines the `revoke_all_refresh_tokens` function and the logic it executes.
- `L304-L313`: Implements this section of logic starting with `Used by logout-all. Returns the count of sessions revoked.`.
- `L315-L332`: Initializes module-level state or configuration such as `now`.
- `L334-L335`: Implements this section of logic starting with `db.commit()`.
- `L338-L359`: Defines `get_active_sessions`. Return metadata for all active sessions (no token values).
