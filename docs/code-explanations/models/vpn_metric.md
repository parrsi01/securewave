# `models/vpn_metric.py`

Purpose: This module defines the database model for vpn metric records used by SecureWave.

## Line Walkthrough

- `L1`: Module or block docstring that describes the responsibility of this section.
- `L3-L5`: Implements this section of logic starting with `This module defines the database model for vpn metric records used by SecureWave.`.
- `L7-L8`: Imports the dependencies used later in this module, including sqlalchemy.
- `L10-L11`: Imports the dependencies used later in this module, including database, utils.
- `L14-L15`: Defines `VPNMetric`. Client-reported VPN connection quality metrics.
- `L17-L21`: Initializes module-level state or configuration such as `__tablename__, __table_args__`.
- `L23-L26`: Initializes module-level state or configuration such as `id, user_id, device_id, server_id`.
- `L28-L32`: Implements this section of logic starting with `# Metrics`.
- `L34-L36`: Implements this section of logic starting with `# Context`.
- `L38`: Initializes module-level state or configuration such as `user`.
- `L40-L52`: Defines the `to_dict` function and the logic it executes.
