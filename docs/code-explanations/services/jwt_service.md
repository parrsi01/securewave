# `services/jwt_service.py`

Purpose: This service module implements the business logic for jwt service operations.

## Line Walkthrough

- `L1`: Module or block docstring that describes the responsibility of this section.
- `L3-L5`: Implements this section of logic starting with `This service module implements the business logic for jwt service operations.`.
- `L7-L10`: Imports the dependencies used later in this module, including logging, uuid, datetime, typing.
- `L12-L15`: Imports the dependencies used later in this module, including fastapi, jose, sqlalchemy.
- `L17-L28`: Implements this section of logic starting with `from database.session import get_db`.
- `L30-L38`: Initializes module-level state or configuration such as `logger, SETTINGS, ENVIRONMENT, ACCESS_SECRET, REFRESH_SECRET, ALGORITHM`.
- `L40-L41`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L43`: Initializes module-level state or configuration such as `oauth2_scheme`.
- `L46-L47`: Defines the `_utcnow` function and the logic it executes.
- `L50-L60`: Defines the `_coerce_expiration` function and the logic it executes.
- `L63-L75`: Defines the `_create_token` function and the logic it executes.
- `L78-L80`: Defines the `create_access_token` function and the logic it executes.
- `L83-L109`: Defines the `_persist_refresh_session` function and the logic it executes.
- `L112-L138`: Defines the `create_refresh_token` function and the logic it executes.
- `L141-L145`: Defines the `decode_token` function and the logic it executes.
- `L148-L167`: Defines the `is_token_jti_revoked` function and the logic it executes.
- `L170-L192`: Defines the `blacklist_token_jti` function and the logic it executes.
- `L194-L210`: Implements this section of logic starting with `db.add(`.
- `L213-L219`: Defines the `revoke_access_token` function and the logic it executes.
- `L221-L229`: Implements this section of logic starting with `blacklist_token_jti(`.
- `L232-L235`: Defines the `verify_refresh_token` function and the logic it executes.
- `L237-L239`: Initializes module-level state or configuration such as `jti`.
- `L241-L242`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L244-L245`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L247-L253`: Initializes module-level state or configuration such as `cached_session`.
- `L255-L274`: Implements this section of logic starting with `session = db.query(AuthRefreshToken).filter(AuthRefreshToken.token_jti == jti).first()`.
- `L277-L285`: Defines the `revoke_refresh_token` function and the logic it executes.
- `L287-L303`: Implements this section of logic starting with `# Keep blacklist table in sync so middleware can reject the refresh token too.`.
- `L306-L314`: Defines the `purge_expired_blacklist_tokens` function and the logic it executes.
- `L317-L343`: Defines the `get_current_user` function and the logic it executes.
- `L345-L348`: Implements this section of logic starting with `user = db.query(User).filter(User.id == int(user_id)).first()`.
