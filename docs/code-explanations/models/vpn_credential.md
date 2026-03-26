# `models/vpn_credential.py`

Purpose: This module defines the database model for vpn credential records used by SecureWave.

## Line Walkthrough

- `L1`: Module or block docstring that describes the responsibility of this section.
- `L3-L5`: Implements this section of logic starting with `This module defines the database model for vpn credential records used by SecureWave.`.
- `L7`: Imports the dependencies used later in this module, including __future__.
- `L9-L10`: Imports the dependencies used later in this module, including sqlalchemy.
- `L12-L13`: Imports the dependencies used later in this module, including database, utils.
- `L16-L18`: Defines the `VPNCredential` class and the behavior it groups together.
- `L20-L24`: Implements this section of logic starting with `Rationale:`.
- `L26-L35`: Initializes module-level state or configuration such as `__tablename__, __table_args__, name`.
- `L37-L40`: Initializes module-level state or configuration such as `id, user_id, device_id, server_id`.
- `L42-L55`: Initializes module-level state or configuration such as `protocol, credential_type, username, password_encrypted, cert_serial, cert_fingerprint_sha256`.
- `L57-L58`: Initializes module-level state or configuration such as `created_at, updated_at`.
- `L60-L63`: Implements this section of logic starting with `# Relationships (optional, but useful for admin tooling)`.
- `L65-L70`: Defines the `__repr__` function and the logic it executes.
