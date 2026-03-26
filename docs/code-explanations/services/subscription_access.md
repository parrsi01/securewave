# `services/subscription_access.py`

Purpose: This service module implements the business logic for subscription access operations.

## Line Walkthrough

- `L1-L2`: Module or block docstring that describes the responsibility of this section.
- `L4-L7`: Implements this section of logic starting with `Enforces active/trial subscriptions and revokes peers on expiration.`.
- `L9-L12`: Imports the dependencies used later in this module, including os, logging, datetime, typing.
- `L14-L15`: Imports the dependencies used later in this module, including fastapi, sqlalchemy.
- `L17-L21`: Imports the dependencies used later in this module, including models, services.
- `L23`: Initializes module-level state or configuration such as `logger`.
- `L25-L27`: Initializes module-level state or configuration such as `FREE_TIER_MONTHLY_GB, FREE_TIER_MONTHLY_BYTES, FREE_TIER_DEVICE_LIMIT`.
- `L30-L39`: Defines the `_get_active_subscription` function and the logic it executes.
- `L42-L51`: Defines `revoke_user_peers`. Revoke all active peers for a user and attempt server removal.
- `L53-L54`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L56-L61`: Attempts a potentially fragile operation and relies on later branches to handle failures safely.
- `L63-L66`: Loops over a collection to apply the same work to each item.
- `L68-L73`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L75-L79`: Initializes module-level state or configuration such as `peer.is_revoked, peer.is_active, peer.device_state, peer.revoked_at`.
- `L81-L82`: Implements this section of logic starting with `db.commit()`.
- `L85-L97`: Defines `_sync_user_usage`. Best-effort sync of peer usage from WireGuard servers.
- `L99-L109`: Attempts a potentially fragile operation and relies on later branches to handle failures safely.
- `L111-L130`: Loops over a collection to apply the same work to each item.
- `L132`: Implements this section of logic starting with `db.commit()`.
- `L135-L139`: Defines the `_user_bytes_used` function and the logic it executes.
- `L142-L143`: Defines the `enforce_free_tier_cap` function and the logic it executes.
- `L145-L167`: Implements this section of logic starting with `This is called for users who have NO active subscription.  If the`.
- `L170-L173`: Defines the `require_active_subscription` function and the logic it executes.
- `L175-L178`: Implements this section of logic starting with `Free-tier users (no subscription record) are permitted as long as they`.
- `L180-L186`: Implements this section of logic starting with `Raises ``HTTPException 402`` only when:`.
- `L188`: Initializes module-level state or configuration such as `subscription`.
- `L190-L193`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L195-L203`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L205`: Returns a value from the current function.
- `L208-L210`: Comment block that explains the next section: =========================================================================.
- `L212-L214`: Defines `is_free_tier`. Return True when the user has no active paid subscription.
- `L217-L218`: Defines the `get_effective_device_limit` function and the logic it executes.
- `L220-L227`: Implements this section of logic starting with `Free tier: 1 device (configurable via FREE_TIER_DEVICE_LIMIT env).`.
- `L229-L231`: Initializes module-level state or configuration such as `sub`.
- `L233-L240`: Initializes module-level state or configuration such as `plan, limits`.
