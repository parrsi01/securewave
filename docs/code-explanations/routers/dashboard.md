# `routers/dashboard.py`

Purpose: This module exposes API handlers for dashboard features in the SecureWave backend.

## Line Walkthrough

- `L1`: Module or block docstring that describes the responsibility of this section.
- `L3-L5`: Implements this section of logic starting with `This module exposes API handlers for dashboard features in the SecureWave backend.`.
- `L7-L8`: Imports the dependencies used later in this module, including fastapi, sqlalchemy.
- `L10-L13`: Imports the dependencies used later in this module, including database, models, services.
- `L15-L16`: Initializes module-level state or configuration such as `router, subscription_service`.
- `L19-L26`: Registers the `user_info` endpoint with the API router.
- `L29-L32`: Registers the `dashboard_info` endpoint with the API router.
- `L34-L43`: Initializes module-level state or configuration such as `subscription_data`.
- `L45-L51`: Returns a value from the current function.
- `L54-L63`: Registers the `subscription` endpoint with the API router.
