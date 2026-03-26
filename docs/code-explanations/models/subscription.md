# `models/subscription.py`

Purpose: This module defines the database model for subscription records used by SecureWave.

## Line Walkthrough

- `L1`: Module or block docstring that describes the responsibility of this section.
- `L3-L5`: Implements this section of logic starting with `This module defines the database model for subscription records used by SecureWave.`.
- `L7-L8`: Imports the dependencies used later in this module, including datetime, typing.
- `L10-L11`: Imports the dependencies used later in this module, including sqlalchemy.
- `L13-L14`: Imports the dependencies used later in this module, including database, utils.
- `L17-L22`: Defines `Subscription`. Production-grade subscription model for payment processing Supports Stripe and PayPal with full billing automation.
- `L24-L26`: Implements this section of logic starting with `# Primary identification`.
- `L28-L30`: Implements this section of logic starting with `# Plan details`.
- `L32-L33`: Implements this section of logic starting with `# Payment provider (stripe or paypal)`.
- `L35-L36`: Implements this section of logic starting with `# Status (active, trialing, past_due, canceled, incomplete, incomplete_expired, unpaid)`.
- `L38-L42`: Implements this section of logic starting with `# Stripe integration fields`.
- `L44-L47`: Implements this section of logic starting with `# PayPal integration fields`.
- `L49-L52`: Implements this section of logic starting with `# Billing details`.
- `L54-L62`: Implements this section of logic starting with `# Important dates`.
- `L64-L67`: Implements this section of logic starting with `# Cancellation tracking`.
- `L69-L73`: Implements this section of logic starting with `# Payment tracking`.
- `L75-L77`: Implements this section of logic starting with `# Renewal tracking`.
- `L79-L81`: Implements this section of logic starting with `# Extra data and notes`.
- `L83-L84`: Implements this section of logic starting with `# Relationships`.
- `L86-L87`: Defines the `__repr__` function and the logic it executes.
- `L89-L92`: Applies decorators and defines `is_active` with the wrapped behavior declared above it.
- `L94-L97`: Applies decorators and defines `is_trial` with the wrapped behavior declared above it.
- `L99-L102`: Applies decorators and defines `is_canceled` with the wrapped behavior declared above it.
- `L104-L107`: Applies decorators and defines `is_past_due` with the wrapped behavior declared above it.
- `L109-L115`: Applies decorators and defines `days_until_renewal` with the wrapped behavior declared above it.
- `L117-L120`: Applies decorators and defines `is_stripe` with the wrapped behavior declared above it.
- `L122-L125`: Applies decorators and defines `is_paypal` with the wrapped behavior declared above it.
- `L127-L129`: Defines the `to_dict` function and the logic it executes.
- `L131-L132`: Implements this section of logic starting with `Args:`.
- `L134-L157`: Implements this section of logic starting with `Returns:`.
- `L159-L169`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L171`: Returns a value from the current function.
