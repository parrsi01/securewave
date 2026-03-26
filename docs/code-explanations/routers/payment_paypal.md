# `routers/payment_paypal.py`

Purpose: This module exposes API handlers for payment paypal features in the SecureWave backend.

## Line Walkthrough

- `L1`: Module or block docstring that describes the responsibility of this section.
- `L3-L5`: Implements this section of logic starting with `This module exposes API handlers for payment paypal features in the SecureWave backend.`.
- `L7-L9`: Imports the dependencies used later in this module, including fastapi, pydantic, sqlalchemy.
- `L11-L15`: Imports the dependencies used later in this module, including database, models, services.
- `L17-L19`: Initializes module-level state or configuration such as `router, paypal_service, subscription_service`.
- `L22-L23`: Defines the `PaypalOrderRequest` class and the behavior it groups together.
- `L26-L33`: Registers the `create_order` endpoint with the API router.
- `L36-L42`: Registers the `capture` endpoint with the API router.
