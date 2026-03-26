# `models/vpn_connection.py`

Purpose: This module defines the database model for vpn connection records used by SecureWave.

## Line Walkthrough

- `L1`: Module or block docstring that describes the responsibility of this section.
- `L3-L5`: Implements this section of logic starting with `This module defines the database model for vpn connection records used by SecureWave.`.
- `L7`: Imports the dependencies used later in this module, including datetime.
- `L9-L10`: Imports the dependencies used later in this module, including sqlalchemy.
- `L12-L13`: Imports the dependencies used later in this module, including database, utils.
- `L16-L18`: Defines `VPNConnection`. VPN connection tracking for monitoring and quality feedback.
- `L20-L22`: Initializes module-level state or configuration such as `id, user_id, server_id`.
- `L24-L28`: Implements this section of logic starting with `# Connection details`.
- `L30-L34`: Implements this section of logic starting with `# Quality metrics (for optimizer feedback)`.
- `L36-L38`: Implements this section of logic starting with `# Relationships`.
- `L40-L42`: Defines the `__repr__` function and the logic it executes.
- `L44-L47`: Applies decorators and defines `is_active` with the wrapped behavior declared above it.
- `L49-L55`: Applies decorators and defines `duration_seconds` with the wrapped behavior declared above it.
- `L57-L70`: Defines `to_dict`. Convert connection to dictionary for API responses.
