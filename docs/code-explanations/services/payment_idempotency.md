# `services/payment_idempotency.py`

Purpose: This service module implements the business logic for payment idempotency operations.

## Line Walkthrough

- `L1`: Module or block docstring that describes the responsibility of this section.
- `L3-L5`: Implements this section of logic starting with `This service module implements the business logic for payment idempotency operations.`.
- `L7`: Imports the dependencies used later in this module, including __future__.
- `L9-L14`: Imports the dependencies used later in this module, including hashlib, json, os, uuid, dataclasses, typing.
- `L16-L17`: Imports the dependencies used later in this module, including sqlalchemy.
- `L19-L21`: Imports the dependencies used later in this module, including models, utils.
- `L24-L25`: Defines the `_stable_json_dumps` function and the logic it executes.
- `L28-L29`: Defines the `sha256_hex` function and the logic it executes.
- `L32-L33`: Defines the `request_hash_from_payload` function and the logic it executes.
- `L36-L42`: Defines the `_idempotency_window_seconds` function and the logic it executes.
- `L45-L51`: Defines the `_idempotency_stale_after_seconds` function and the logic it executes.
- `L54-L56`: Defines the `_make_key` function and the logic it executes.
- `L59-L62`: Applies decorators and defines `IdempotencyOutcome` with the wrapped behavior declared above it.
- `L65-L75`: Defines the `run_idempotent` function and the logic it executes.
- `L77-L85`: Implements this section of logic starting with `- Prevents double-submits (same user + request fingerprint within window).`.
- `L87-L110`: Implements this section of logic starting with `# Harden checkout flow against concurrent conflicting requests for the`.
- `L112-L123`: Initializes module-level state or configuration such as `record, provider, operation, user_id, request_hash, bucket`.
- `L125-L146`: Initializes module-level state or configuration such as `created`.
- `L148-L149`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L151-L160`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L162-L168`: Implements this section of logic starting with `# Retry path: reuse the same provider idempotency key so Stripe is protected too.`.
- `L170-L178`: Attempts a potentially fragile operation and relies on later branches to handle failures safely.
- `L180-L184`: Initializes module-level state or configuration such as `record.status, record.response_json, record.updated_at`.
- `L186`: Returns a value from the current function.
