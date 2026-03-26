# `routers/admin.py`

Purpose: This module exposes API handlers for admin features in the SecureWave backend.

## Line Walkthrough

- `L1-L9`: Module or block docstring that describes the responsibility of this section.
- `L11-L13`: Imports the dependencies used later in this module, including fastapi, pydantic, sqlalchemy.
- `L15-L19`: Imports the dependencies used later in this module, including config, database, models, services.
- `L21-L22`: Initializes module-level state or configuration such as `router, SETTINGS`.
- `L24-L29`: Implements this section of logic starting with `# WireGuard server details (SSH)`.
- `L32-L36`: Defines the `_resolve_ssh` function and the logic it executes.
- `L39-L46`: Defines the `_build_ssh_command` function and the logic it executes.
- `L49-L55`: Defines the `_validate_wg_peer_inputs` function and the logic it executes.
- `L58-L63`: Defines the `PeerInfo` class and the behavior it groups together.
- `L66-L67`: Defines the `RegisterPeerRequest` class and the behavior it groups together.
- `L70-L76`: Defines the `RegisterPeerResponse` class and the behavior it groups together.
- `L79-L86`: Defines `require_admin`. Dependency that requires admin privileges.
- `L89-L98`: Registers the `list_pending_peers` endpoint with the API router.
- `L100-L104`: Implements this section of logic starting with `# Find users with wg_public_key who aren't registered yet`.
- `L106-L115`: Returns a value from the current function.
- `L118-L124`: Registers the `list_all_peers` endpoint with the API router.
- `L126-L128`: Initializes module-level state or configuration such as `users_with_keys`.
- `L130-L139`: Returns a value from the current function.
- `L142-L153`: Registers the `register_peer` endpoint with the API router.
- `L155-L156`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L158-L159`: Initializes module-level state or configuration such as `wg_service, client_ip`.
- `L161`: Implements this section of logic starting with `_validate_wg_peer_inputs(user.wg_public_key, client_ip)`.
- `L163-L166`: Implements this section of logic starting with `# Build the wg set command`.
- `L168-L174`: Attempts a potentially fragile operation and relies on later branches to handle failures safely.
- `L176-L179`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L181-L197`: Returns a value from the current function.
- `L199-L216`: Handles a failure from the preceding `try` block.
- `L219-L227`: Registers the `register_all_pending_peers` endpoint with the API router.
- `L229-L232`: Initializes module-level state or configuration such as `pending_users`.
- `L234-L235`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L237-L239`: Loops over a collection to apply the same work to each item.
- `L241-L245`: Implements this section of logic starting with `# Build bulk command`.
- `L247-L248`: Implements this section of logic starting with `commands.append("sudo wg-quick save wg0")`.
- `L250-L257`: Initializes module-level state or configuration such as `results`.
- `L259-L269`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L271-L281`: Returns a value from the current function.
- `L283-L296`: Handles a failure from the preceding `try` block.
- `L299-L310`: Registers the `mark_peer_registered` endpoint with the API router.
- `L312-L313`: Initializes module-level state or configuration such as `user.wg_peer_registered`.
- `L315`: Returns a value from the current function.
- `L318-L329`: Registers the `get_peer_command` endpoint with the API router.
- `L331-L332`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L334-L335`: Initializes module-level state or configuration such as `wg_service, client_ip`.
- `L337-L344`: Returns a value from the current function.
