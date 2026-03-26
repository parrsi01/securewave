# `services/shared_security_state.py`

Purpose: This service module implements the business logic for shared security state operations.

## Line Walkthrough

- `L1`: Module or block docstring that describes the responsibility of this section.
- `L3-L5`: Implements this section of logic starting with `This service module implements the business logic for shared security state operations.`.
- `L7`: Imports the dependencies used later in this module, including __future__.
- `L9-L15`: Imports the dependencies used later in this module, including json, logging, threading, time, datetime, functools, typing.
- `L17`: Imports the dependencies used later in this module, including redis.
- `L19`: Imports the dependencies used later in this module, including config.
- `L22-L24`: Initializes module-level state or configuration such as `logger, SETTINGS, _KEY_PREFIX`.
- `L27-L33`: Defines the `SecurityStateBackend` class and the behavior it groups together.
- `L36-L37`: Defines the `_utcnow` function and the logic it executes.
- `L40-L46`: Defines the `_ttl_until` function and the logic it executes.
- `L49-L52`: Defines the `_InMemorySecurityStateBackend` class and the behavior it groups together.
- `L54-L58`: Defines the `_purge_expired` function and the logic it executes.
- `L60-L70`: Defines the `incr` function and the logic it executes.
- `L72-L75`: Defines the `set_json` function and the logic it executes.
- `L77-L89`: Defines the `get_json` function and the logic it executes.
- `L91-L94`: Defines the `exists` function and the logic it executes.
- `L96-L98`: Defines the `delete` function and the logic it executes.
- `L100-L105`: Defines the `delete_prefix` function and the logic it executes.
- `L108-L110`: Defines the `_RedisSecurityStateBackend` class and the behavior it groups together.
- `L112-L116`: Defines the `incr` function and the logic it executes.
- `L118-L119`: Defines the `set_json` function and the logic it executes.
- `L121-L129`: Defines the `get_json` function and the logic it executes.
- `L131-L132`: Defines the `exists` function and the logic it executes.
- `L134-L135`: Defines the `delete` function and the logic it executes.
- `L137-L141`: Defines the `delete_prefix` function and the logic it executes.
- `L144-L145`: Initializes module-level state or configuration such as `_memory_backend`.
- `L148-L149`: Defines the `_redis_enabled` function and the logic it executes.
- `L152-L164`: Applies decorators and defines `_redis_backend` with the wrapped behavior declared above it.
- `L167-L178`: Defines the `_backend` function and the logic it executes.
- `L181-L183`: Defines the `set_shared_security_backend_for_tests` function and the logic it executes.
- `L186-L187`: Defines the `build_in_memory_security_state_backend` function and the logic it executes.
- `L190-L202`: Defines the `clear_shared_security_state_for_tests` function and the logic it executes.
- `L205-L206`: Defines the `_key` function and the logic it executes.
- `L209-L212`: Defines the `increment_rate_limit_window` function and the logic it executes.
- `L215-L233`: Defines the `remember_revoked_token` function and the logic it executes.
- `L236-L237`: Defines the `is_token_revoked` function and the logic it executes.
- `L240-L265`: Defines the `register_refresh_session` function and the logic it executes.
- `L268-L269`: Defines the `get_refresh_session` function and the logic it executes.
- `L272-L290`: Defines the `revoke_refresh_session` function and the logic it executes.
- `L293-L302`: Defines the `_parse_iso_datetime` function and the logic it executes.
