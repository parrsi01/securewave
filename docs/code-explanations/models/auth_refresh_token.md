# `models/auth_refresh_token.py`

Purpose: This module defines the database model for auth refresh token records used by SecureWave.

## Line Walkthrough

- `L1-L3`: Module or block docstring that describes the responsibility of this section.
- `L5-L6`: Imports the dependencies used later in this module, including sqlalchemy.
- `L8-L9`: Imports the dependencies used later in this module, including database, utils.
- `L12-L13`: Defines the `AuthRefreshToken` class and the behavior it groups together.
- `L15-L23`: Initializes module-level state or configuration such as `id, user_id, token_jti, user_agent, ip_address, issued_at`.
- `L25`: Initializes module-level state or configuration such as `user`.
