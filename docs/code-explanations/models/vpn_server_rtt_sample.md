# `models/vpn_server_rtt_sample.py`

Purpose: This module defines the database model for vpn server rtt sample records used by SecureWave.

## Line Walkthrough

- `L1`: Module or block docstring that describes the responsibility of this section.
- `L3-L5`: Implements this section of logic starting with `This module defines the database model for vpn server rtt sample records used by SecureWave.`.
- `L7-L8`: Imports the dependencies used later in this module, including sqlalchemy.
- `L10-L11`: Imports the dependencies used later in this module, including database, utils.
- `L14-L16`: Defines the `VPNServerRTTSample` class and the behavior it groups together.
- `L18-L21`: Implements this section of logic starting with `Notes:`.
- `L23-L26`: Initializes module-level state or configuration such as `__tablename__, __table_args__`.
- `L28-L32`: Initializes module-level state or configuration such as `id, vpn_server_id, observed_at, rtt_ms, source`.
- `L34`: Initializes module-level state or configuration such as `server`.
