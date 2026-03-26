# `config/settings.py`

Purpose: This configuration module defines settings and security policy for settings.

## Line Walkthrough

- `L1`: Module or block docstring that describes the responsibility of this section.
- `L3-L5`: Implements this section of logic starting with `This configuration module defines settings and security policy for settings.`.
- `L7`: Imports the dependencies used later in this module, including __future__.
- `L9-L17`: Imports the dependencies used later in this module, including hashlib, hmac, os, secrets, dataclasses, functools, pathlib, typing, ....
- `L19-L21`: Imports the dependencies used later in this module, including cryptography, dotenv, sqlalchemy.
- `L23`: Imports the dependencies used later in this module, including config.
- `L26-L33`: Initializes module-level state or configuration such as `PROJECT_ROOT, _DEFAULT_DATABASE_URL, _DEFAULT_API_BASE_URL, _DEFAULT_VPN_SERVER_ENDPOINT, _DEFAULT_JWT_SECRET, _ALLOWED_COOKIE_SAMESITE`.
- `L36-L37`: Defines `ConfigurationError`. Raised when startup configuration is invalid.
- `L39-L41`: Defines the `__init__` function and the logic it executes.
- `L44-L103`: Applies decorators and defines `Settings` with the wrapped behavior declared above it.
- `L106-L111`: Defines the `_load_environment_files` function and the logic it executes.
- `L114-L118`: Defines the `_clean` function and the logic it executes.
- `L121-L129`: Defines the `_parse_bool` function and the logic it executes.
- `L132-L150`: Defines the `_parse_int` function and the logic it executes.
- `L153-L164`: Defines the `_normalize_http_url` function and the logic it executes.
- `L166-L171`: Initializes module-level state or configuration such as `parsed`.
- `L173-L182`: Initializes module-level state or configuration such as `normalized`.
- `L185-L189`: Defines the `_normalize_wireguard_endpoint` function and the logic it executes.
- `L191-L197`: Initializes module-level state or configuration such as `parsed, host`.
- `L199-L201`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L203-L206`: Initializes module-level state or configuration such as `normalized_host`.
- `L209-L220`: Defines the `_validate_database_url` function and the logic it executes.
- `L222-L224`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L227-L229`: Defines the `_derive_secret` function and the logic it executes.
- `L232-L234`: Defines the `_validate_secret_strength` function and the logic it executes.
- `L237-L244`: Defines the `_validate_fernet_key` function and the logic it executes.
- `L247-L260`: Defines the `_resolve_value` function and the logic it executes.
- `L263-L265`: Defines the `_build_settings` function and the logic it executes.
- `L267-L269`: Initializes module-level state or configuration such as `environment`.
- `L271-L274`: Initializes module-level state or configuration such as `log_level`.
- `L276-L293`: Initializes module-level state or configuration such as `raw_app_url, _, raw_api_base_url`.
- `L295-L308`: Initializes module-level state or configuration such as `database_url_raw, _`.
- `L310-L342`: Initializes module-level state or configuration such as `db_pool_size, default, errors, minimum, db_max_overflow`.
- `L344-L357`: Initializes module-level state or configuration such as `raw_jwt_secret, _, warnings`.
- `L359-L361`: Initializes module-level state or configuration such as `jwt_secret, access_token_secret, refresh_token_secret`.
- `L363-L366`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L368-L385`: Initializes module-level state or configuration such as `access_token_expire_minutes, default, errors, minimum, refresh_token_expire_minutes`.
- `L387-L399`: Initializes module-level state or configuration such as `telemetry_value, _, warnings, telemetry_enabled`.
- `L401-L407`: Initializes module-level state or configuration such as `auth_encryption_key, wg_encryption_key`.
- `L409-L412`: Initializes module-level state or configuration such as `origins_raw, cors_origins`.
- `L414-L417`: Initializes module-level state or configuration such as `cookie_samesite`.
- `L419-L424`: Initializes module-level state or configuration such as `redis_url`.
- `L426-L434`: Initializes module-level state or configuration such as `raw_vpn_server_endpoint, _, warnings`.
- `L436-L474`: Initializes module-level state or configuration such as `wg_data_dir, raw_dns`.
- `L476-L492`: Initializes module-level state or configuration such as `email_provider, smtp_host, smtp_port, default, errors, minimum`.
- `L494-L510`: Initializes module-level state or configuration such as `slow_query_threshold_ms, default, errors, minimum, slow_api_threshold_ms`.
- `L512-L572`: Initializes module-level state or configuration such as `settings, environment, testing, is_production, log_level, docs_enabled`.
- `L575-L578`: Defines the `collect_configuration_errors` function and the logic it executes.
- `L581-L587`: Applies decorators and defines `_cached_settings` with the wrapped behavior declared above it.
- `L590-L593`: Defines the `get_settings` function and the logic it executes.
- `L596-L598`: Defines the `env_file_has_value` function and the logic it executes.
