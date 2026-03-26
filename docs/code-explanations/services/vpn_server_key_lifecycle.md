# `services/vpn_server_key_lifecycle.py`

Purpose: This service module implements the business logic for vpn server key lifecycle operations.

## Line Walkthrough

- `L1-L3`: Module or block docstring that describes the responsibility of this section.
- `L5`: Imports the dependencies used later in this module, including __future__.
- `L7-L9`: Imports the dependencies used later in this module, including os, datetime, typing.
- `L11`: Imports the dependencies used later in this module, including sqlalchemy.
- `L13-L21`: Implements this section of logic starting with `from models.vpn_server import VPNServer`.
- `L24-L25`: Defines `VPNServerKeyLifecycleService`. Service for VPN node seed/rotation workflows.
- `L27-L29`: Defines the `__init__` function and the logic it executes.
- `L31-L56`: Defines `seed_add_node`. Create or update a VPN node in the registry.
- `L58-L61`: Implements this section of logic starting with `existing = self.db.query(VPNServer).filter(VPNServer.server_id == safe_server_id).first()`.
- `L63-L85`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L87-L113`: Initializes module-level state or configuration such as `server, server_id, location, country, country_code, city`.
- `L115-L129`: Defines `rotate_server_key`. Rotate one server keypair and optionally apply on the remote node.
- `L131-L133`: Initializes module-level state or configuration such as `new_private_key, new_public_key, encrypted_private`.
- `L135-L143`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L145-L153`: Initializes module-level state or configuration such as `ok, message, remote_public_key, interface`.
- `L155-L157`: Initializes module-level state or configuration such as `now, rotation_days, next_rotation`.
- `L159-L166`: Initializes module-level state or configuration such as `server.wg_public_key, server.wg_private_key_encrypted, server.wg_key_version, server.wg_last_rotated_at, server.wg_next_rotation_at`.
- `L168-L174`: Returns a value from the current function.
