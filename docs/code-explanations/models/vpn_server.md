# `models/vpn_server.py`

Purpose: This module defines the database model for vpn server records used by SecureWave.

## Line Walkthrough

- `L1`: Module or block docstring that describes the responsibility of this section.
- `L3-L5`: Implements this section of logic starting with `This module defines the database model for vpn server records used by SecureWave.`.
- `L7`: Imports the dependencies used later in this module, including datetime.
- `L9-L10`: Imports the dependencies used later in this module, including sqlalchemy.
- `L12-L13`: Imports the dependencies used later in this module, including database, utils.
- `L16-L18`: Defines `VPNServer`. VPN server model for tracking server fleet and metrics.
- `L20-L32`: Initializes module-level state or configuration such as `id, server_id, location, country, country_code, city`.
- `L34-L39`: Implements this section of logic starting with `# Hetzner Infrastructure Details`.
- `L41-L52`: Implements this section of logic starting with `# Network Configuration`.
- `L54-L61`: Implements this section of logic starting with `# ---------------------------------------------------------------------`.
- `L63-L66`: Initializes module-level state or configuration such as `supports_wireguard, supports_openvpn, supports_ikev2, supports_l2tp`.
- `L68-L72`: Implements this section of logic starting with `# OpenVPN (server-side TLS; clients authenticate with username/password)`.
- `L74-L76`: Implements this section of logic starting with `# IKEv2/IPsec (EAP user/pass recommended)`.
- `L78-L79`: Implements this section of logic starting with `# L2TP/IPsec (legacy fallback)`.
- `L81-L84`: Implements this section of logic starting with `# Capacity and limits`.
- `L86-L90`: Implements this section of logic starting with `# Status`.
- `L92-L96`: Implements this section of logic starting with `# Auto-scaling metadata`.
- `L98-L100`: Initializes module-level state or configuration such as `load_score`.
- `L102-L113`: Implements this section of logic starting with `# Real-time metrics (updated by monitoring service)`.
- `L115-L118`: Implements this section of logic starting with `# Failover and redundancy`.
- `L120-L123`: Implements this section of logic starting with `# Performance scoring (for intelligent selection)`.
- `L125-L130`: Implements this section of logic starting with `# Metadata`.
- `L132-L133`: Implements this section of logic starting with `# Relationships`.
- `L135-L136`: Defines the `__repr__` function and the logic it executes.
- `L138-L146`: Applies decorators and defines `is_available` with the wrapped behavior declared above it.
- `L148-L153`: Applies decorators and defines `capacity_percentage` with the wrapped behavior declared above it.
- `L155-L160`: Applies decorators and defines `needs_scaling` with the wrapped behavior declared above it.
- `L162-L167`: Applies decorators and defines `can_scale_down` with the wrapped behavior declared above it.
- `L169-L173`: Defines `compute_load_score`. Derive a 0.0–1.0 composite load score from cpu, memory, and connection ratio.
- `L175-L212`: Defines `to_dict`. Convert server to dictionary for API responses.
- `L214-L222`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L224`: Returns a value from the current function.
- `L226-L261`: Defines `to_admin_dict`. Full details for admin dashboard.
