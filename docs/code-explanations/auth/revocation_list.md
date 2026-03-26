# `auth/revocation_list.py`

Purpose: This authentication module handles revocation list responsibilities for SecureWave.

## Line Walkthrough

- `L1-L2`: Module or block docstring that describes the responsibility of this section.
- `L4-L11`: Implements this section of logic starting with `Design:`.
- `L13`: Imports the dependencies used later in this module, including __future__.
- `L15-L17`: Imports the dependencies used later in this module, including logging, datetime, typing.
- `L19`: Imports the dependencies used later in this module, including sqlalchemy.
- `L21-L22`: Imports the dependencies used later in this module, including config, models.
- `L24-L25`: Initializes module-level state or configuration such as `logger, SETTINGS`.
- `L27-L29`: Implements this section of logic starting with `# ── Redis optional bootstrap ───────────────────────────────────────────────────`.
- `L32-L36`: Defines `_get_redis`. Return a Redis client if configured, else None. Thread-safe via import lock.
- `L38-L40`: Initializes module-level state or configuration such as `redis_url`.
- `L42-L43`: Attempts a potentially fragile operation and relies on later branches to handle failures safely.
- `L45-L51`: Initializes module-level state or configuration such as `client, _redis_client, extra`.
- `L53`: Returns a value from the current function.
- `L56-L58`: Defines `_redis_ttl`. Seconds until the token expires (minimum 1 to avoid immediate eviction).
- `L60-L61`: Initializes module-level state or configuration such as `remaining`.
- `L64-L75`: Implements this section of logic starting with `# ── Public API ─────────────────────────────────────────────────────────────────`.
- `L77-L95`: Implements this section of logic starting with `Writes to DB (durable) and Redis cache (fast lookup) if available.`.
- `L97-L104`: Implements this section of logic starting with `# Redis write (best-effort)`.
- `L107-L109`: Defines the `is_revoked` function and the logic it executes.
- `L111-L120`: Implements this section of logic starting with `Checks Redis first (O(1) lookup) then falls back to DB.`.
- `L122-L127`: Returns a value from the current function.
- `L130-L132`: Defines the `revoke_all_for_user` function and the logic it executes.
- `L134-L136`: Implements this section of logic starting with `Used by logout-all. Returns the count of newly revoked entries.`.
- `L138-L142`: Implements this section of logic starting with `Note: This cannot retroactively revoke access tokens whose JTIs were never`.
- `L144-L154`: Initializes module-level state or configuration such as `now, existing`.
- `L156-L163`: Initializes module-level state or configuration such as `r`.
- `L165`: Returns a value from the current function.
- `L168-L170`: Defines the `purge_expired` function and the logic it executes.
- `L172-L174`: Implements this section of logic starting with `Safe to run as a cron job. Returns the number of rows deleted.`.
- `L176-L182`: Initializes module-level state or configuration such as `deleted`.
- `L185-L188`: Defines `get_revocation_stats`. Admin diagnostic — total and recent revocation counts.
- `L190-L200`: Initializes module-level state or configuration such as `total, last_hour`.
