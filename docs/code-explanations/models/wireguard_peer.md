# `models/wireguard_peer.py`

Purpose: This module defines the database model for wireguard peer records used by SecureWave.

## Line Walkthrough

- `L1-L3`: Module or block docstring that describes the responsibility of this section.
- `L5`: Imports the dependencies used later in this module, including typing.
- `L7-L8`: Imports the dependencies used later in this module, including sqlalchemy.
- `L10-L11`: Imports the dependencies used later in this module, including database, utils.
- `L13-L20`: Initializes module-level state or configuration such as `DEVICE_STATE_ACTIVE, DEVICE_STATE_REVOKED, DEVICE_STATE_EXPIRED, DEVICE_STATES`.
- `L23-L40`: Defines `WireGuardPeer`. WireGuard peer (client) configuration Tracks keys, IP allocations, and server assignments.
- `L42-L44`: Initializes module-level state or configuration such as `id, user_id, server_id`.
- `L46-L48`: Implements this section of logic starting with `# WireGuard keys`.
- `L50-L52`: Implements this section of logic starting with `# Network configuration`.
- `L54-L56`: Implements this section of logic starting with `# Peer details`.
- `L58-L62`: Implements this section of logic starting with `# Status`.
- `L64-L67`: Implements this section of logic starting with `# Key rotation`.
- `L69-L75`: Implements this section of logic starting with `# Usage tracking`.
- `L77-L80`: Implements this section of logic starting with `# Timestamps`.
- `L82-L84`: Implements this section of logic starting with `# Relationships`.
- `L86-L87`: Defines the `__repr__` function and the logic it executes.
- `L89-L94`: Applies decorators and defines `needs_rotation` with the wrapped behavior declared above it.
- `L96-L101`: Applies decorators and defines `is_profile_expired` with the wrapped behavior declared above it.
- `L103-L115`: Applies decorators and defines `effective_device_state` with the wrapped behavior declared above it.
- `L117-L122`: Applies decorators and defines `days_since_rotation` with the wrapped behavior declared above it.
- `L124-L130`: Applies decorators and defines `is_recently_active` with the wrapped behavior declared above it.
- `L132-L154`: Defines `to_dict`. Convert to dictionary.
- `L156-L157`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L159`: Returns a value from the current function.
