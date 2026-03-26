# `models/jwt_blacklist_token.py`

Purpose: This module defines the database model for jwt blacklist token records used by SecureWave.

## Line Walkthrough

- `L1-L3`: Module or block docstring that describes the responsibility of this section.
- `L5-L6`: Imports the dependencies used later in this module, including sqlalchemy.
- `L8-L9`: Imports the dependencies used later in this module, including database, utils.
- `L12-L13`: Defines the `JWTBlacklistToken` class and the behavior it groups together.
- `L15-L21`: Initializes module-level state or configuration such as `id, user_id, token_jti, token_type, reason, revoked_at`.
- `L23`: Initializes module-level state or configuration such as `user`.
