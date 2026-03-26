# `models/webhook_event_receipt.py`

Purpose: This module defines the database model for webhook event receipt records used by SecureWave.

## Line Walkthrough

- `L1`: Module or block docstring that describes the responsibility of this section.
- `L3-L5`: Implements this section of logic starting with `This module defines the database model for webhook event receipt records used by SecureWave.`.
- `L7`: Imports the dependencies used later in this module, including __future__.
- `L9`: Imports the dependencies used later in this module, including sqlalchemy.
- `L11-L12`: Imports the dependencies used later in this module, including database, utils.
- `L15-L17`: Defines the `WebhookEventReceipt` class and the behavior it groups together.
- `L19-L21`: Implements this section of logic starting with `Stores only minimal metadata (no raw payloads) to avoid sensitive data`.
- `L23`: Initializes module-level state or configuration such as `__tablename__`.
- `L25`: Initializes module-level state or configuration such as `id`.
- `L27-L29`: Initializes module-level state or configuration such as `provider, event_id, event_type`.
- `L31-L32`: Initializes module-level state or configuration such as `status, attempt_count`.
- `L34-L35`: Initializes module-level state or configuration such as `payload_hash, last_error`.
- `L37-L38`: Initializes module-level state or configuration such as `received_at, processed_at`.
- `L40-L43`: Initializes module-level state or configuration such as `__table_args__, name`.
