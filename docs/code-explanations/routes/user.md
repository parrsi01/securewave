# `routes/user.py`

Purpose: This module exposes API handlers for user features in the SecureWave backend.

## Line Walkthrough

- `L1-L3`: Module or block docstring that describes the responsibility of this section.
- `L5-L7`: Imports the dependencies used later in this module, including os, datetime, typing.
- `L9-L10`: Imports the dependencies used later in this module, including fastapi, sqlalchemy.
- `L12-L21`: Imports the dependencies used later in this module, including database, models, services, utils.
- `L23-L24`: Initializes module-level state or configuration such as `router, account_router`.
- `L27-L36`: Defines the `_active_subscription` function and the logic it executes.
- `L39-L51`: Defines the `_bytes_used` function and the logic it executes.
- `L53-L61`: Initializes module-level state or configuration such as `stats, stats_total`.
- `L64-L85`: Defines the `_get_or_create_usage_stats` function and the logic it executes.
- `L88-L97`: Defines the `_sync_simulated_usage` function and the logic it executes.
- `L99-L107`: Initializes module-level state or configuration such as `usage, usage.total_bytes_downloaded, usage.total_bytes_uploaded, total_bytes, usage.total_data_gb, usage.current_month_data_gb`.
- `L109-L121`: Initializes module-level state or configuration such as `active_connection`.
- `L123`: Implements this section of logic starting with `db.commit()`.
- `L126-L134`: Defines the `_speed_policy` function and the logic it executes.
- `L137-L145`: Defines the `build_account_usage_payload` function and the logic it executes.
- `L147-L157`: Initializes module-level state or configuration such as `devices_count, username, speed_down, speed_up, renewal`.
- `L159-L173`: Returns a value from the current function.
- `L176-L182`: Registers the `get_user_plan` endpoint with the API router.
- `L184-L188`: Implements this section of logic starting with `Response shape matches the Flutter app's `UserPlan.fromJson`.`.
- `L190-L201`: Initializes module-level state or configuration such as `free_cap_gb`.
- `L203-L206`: Initializes module-level state or configuration such as `plan_name, speed_down, speed_up, premium_cap_gb, data_cap_gb`.
- `L208-L217`: Initializes module-level state or configuration such as `renewal`.
- `L220-L228`: Registers the `get_account_usage` endpoint with the API router.
