# `models/invoice.py`

Purpose: This module defines the database model for invoice records used by SecureWave.

## Line Walkthrough

- `L1`: Module or block docstring that describes the responsibility of this section.
- `L3-L5`: Implements this section of logic starting with `This module defines the database model for invoice records used by SecureWave.`.
- `L7-L8`: Imports the dependencies used later in this module, including datetime, typing.
- `L10-L11`: Imports the dependencies used later in this module, including sqlalchemy.
- `L13-L14`: Imports the dependencies used later in this module, including database, utils.
- `L17-L22`: Defines `Invoice`. Invoice model for tracking all payment transactions Supports Stripe and PayPal invoices.
- `L24-L27`: Implements this section of logic starting with `# Primary identification`.
- `L29-L30`: Implements this section of logic starting with `# Invoice identification`.
- `L32-L33`: Implements this section of logic starting with `# Payment provider`.
- `L35-L40`: Implements this section of logic starting with `# Provider IDs`.
- `L42-L47`: Implements this section of logic starting with `# Invoice details`.
- `L49-L52`: Implements this section of logic starting with `# Tax and fees`.
- `L54-L55`: Implements this section of logic starting with `# Status (draft, open, paid, void, uncollectible)`.
- `L57-L61`: Implements this section of logic starting with `# Important dates`.
- `L63-L65`: Implements this section of logic starting with `# Billing period`.
- `L67-L70`: Implements this section of logic starting with `# Payment method`.
- `L72-L74`: Implements this section of logic starting with `# Retry tracking for failed payments`.
- `L76-L79`: Implements this section of logic starting with `# PDF and receipt`.
- `L81-L83`: Implements this section of logic starting with `# Extra data`.
- `L85-L87`: Implements this section of logic starting with `# Relationships`.
- `L89-L90`: Defines the `__repr__` function and the logic it executes.
- `L92-L95`: Applies decorators and defines `is_paid` with the wrapped behavior declared above it.
- `L97-L100`: Applies decorators and defines `is_open` with the wrapped behavior declared above it.
- `L102-L107`: Applies decorators and defines `is_overdue` with the wrapped behavior declared above it.
- `L109-L115`: Applies decorators and defines `days_overdue` with the wrapped behavior declared above it.
- `L117-L119`: Defines the `to_dict` function and the logic it executes.
- `L121-L122`: Implements this section of logic starting with `Args:`.
- `L124-L153`: Implements this section of logic starting with `Returns:`.
- `L155-L160`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L162`: Returns a value from the current function.
