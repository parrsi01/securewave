# `services/hashing_service.py`

Purpose: This service module implements the business logic for hashing service operations.

## Line Walkthrough

- `L1-L2`: Module or block docstring that describes the responsibility of this section.
- `L4-L10`: Implements this section of logic starting with `Security properties:`.
- `L12`: Imports the dependencies used later in this module, including os.
- `L14`: Imports the dependencies used later in this module, including config.
- `L16-L21`: Implements this section of logic starting with `# ---------------------------------------------------------------------------`.
- `L23-L25`: Initializes module-level state or configuration such as `_HAS_ARGON2`.
- `L27-L35`: Implements this section of logic starting with `# ---------------------------------------------------------------------------`.
- `L37`: Initializes module-level state or configuration such as `SETTINGS`.
- `L39-L40`: Initializes module-level state or configuration such as `_MAX_INPUT_BYTES, _BCRYPT_MAX_BYTES`.
- `L43-L44`: Defines the `_is_testing` function and the logic it executes.
- `L47-L50`: Defines the `_make_argon2_hasher` function and the logic it executes.
- `L53-L60`: Defines the `_bcrypt_rounds` function and the logic it executes.
- `L63-L67`: Initializes module-level state or configuration such as `_bcrypt_ctx`.
- `L70-L74`: Defines the `_validate_input` function and the logic it executes.
- `L77-L84`: Defines `hash_password`. Hash a password.  Uses Argon2id when available, bcrypt otherwise.
- `L87-L105`: Defines `verify_password`. Verify plain against hash.  Auto-detects Argon2 vs bcrypt.
- `L108-L120`: Defines `needs_rehash`. Return True if the hash should be upgraded (bcrypt → Argon2id, or stale Argon2 params).
