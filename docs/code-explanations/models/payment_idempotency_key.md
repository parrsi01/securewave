# `models/payment_idempotency_key.py`

Purpose: This module defines the database model for payment idempotency key records used by SecureWave.

## Line Walkthrough

- `L1`: Module or block docstring that describes the responsibility of this section.
- `L3-L5`: Implements this section of logic starting with `This module defines the database model for payment idempotency key records used by SecureWave.`.
- `L7`: Imports the dependencies used later in this module, including __future__.
- `L9-L10`: Imports the dependencies used later in this module, including sqlalchemy.
- `L12-L13`: Imports the dependencies used later in this module, including database, utils.
- `L16-L18`: Defines the `PaymentIdempotencyKey` class and the behavior it groups together.
- `L20-L22`: Implements this section of logic starting with `This is intentionally provider-agnostic so we can harden payment flows without`.
- `L24`: Initializes module-level state or configuration such as `__tablename__`.
- `L26`: Initializes module-level state or configuration such as `id`.
- `L28-L29`: Initializes module-level state or configuration such as `provider, operation`.
- `L31`: Initializes module-level state or configuration such as `user_id`.
- `L33-L34`: Implements this section of logic starting with `# Stable fingerprint of the request inputs (sha256 hex) to detect misuse.`.
- `L36-L37`: Implements this section of logic starting with `# Time bucket (floor(epoch/window_seconds)) to bound idempotency lifetime.`.
- `L39-L40`: Implements this section of logic starting with `# The idempotency key we also pass to the provider (when supported).`.
- `L42-L43`: Initializes module-level state or configuration such as `status, attempt_count`.
- `L45-L47`: Implements this section of logic starting with `# Provider/API response payload captured for exact replay.`.
- `L49-L50`: Initializes module-level state or configuration such as `created_at, updated_at`.
- `L52`: Initializes module-level state or configuration such as `user`.
- `L54-L69`: Initializes module-level state or configuration such as `__table_args__, name`.
