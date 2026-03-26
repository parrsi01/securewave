# `routers/payment_stripe.py`

Purpose: This module exposes API handlers for payment stripe features in the SecureWave backend.

## Line Walkthrough

- `L1-L2`: Module or block docstring that describes the responsibility of this section.
- `L4-L10`: Implements this section of logic starting with `Provides direct Stripe endpoints under /api/payments/stripe/*:`.
- `L12-L15`: Imports the dependencies used later in this module, including logging, os, hashlib, typing.
- `L17-L22`: Imports the dependencies used later in this module, including fastapi, pydantic, sqlalchemy, slowapi.
- `L24-L33`: Imports the dependencies used later in this module, including config, database, models, services, utils.
- `L35`: Initializes module-level state or configuration such as `logger`.
- `L37-L40`: Initializes module-level state or configuration such as `router, limiter, SETTINGS, IS_TESTING`.
- `L43-L48`: Defines the `rate_limit` function and the logic it executes.
- `L51-L53`: Defines `_stripe_configured`. Return True if the Stripe secret key is set.
- `L56-L60`: Defines the `_base_url` function and the logic it executes.
- `L63-L65`: Comment block that explains the next section: ---------------------------------------------------------------------------.
- `L67-L70`: Defines the `CheckoutSessionRequest` class and the behavior it groups together.
- `L73-L74`: Defines the `PortalSessionRequest` class and the behavior it groups together.
- `L77-L79`: Comment block that explains the next section: ---------------------------------------------------------------------------.
- `L81-L90`: Registers the `create_checkout_session` endpoint with the API router.
- `L92-L101`: Implements this section of logic starting with `Returns the checkout session URL that the frontend should redirect to.`.
- `L103-L109`: Implements this section of logic starting with `# Free plan does not require Stripe`.
- `L111-L116`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L118-L124`: Initializes module-level state or configuration such as `price_key`.
- `L126`: Initializes module-level state or configuration such as `base`.
- `L128-L142`: Attempts a potentially fragile operation and relies on later branches to handle failures safely.
- `L144-L155`: Implements this section of logic starting with `# Ensure the user has a Stripe customer ID`.
- `L157-L161`: Initializes module-level state or configuration such as `idempotency_payload`.
- `L163-L175`: Defines the `_execute` function and the logic it executes.
- `L177-L184`: Initializes module-level state or configuration such as `outcome, provider, operation, user_id, request_payload, execute`.
- `L186-L188`: Initializes module-level state or configuration such as `response`.
- `L190-L196`: Handles a failure from the preceding `try` block.
- `L199-L201`: Comment block that explains the next section: ---------------------------------------------------------------------------.
- `L203-L211`: Registers the `stripe_webhook` endpoint with the API router.
- `L213-L221`: Implements this section of logic starting with `The endpoint reads the raw request body and verifies the Stripe-Signature`.
- `L223-L228`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L230`: Initializes module-level state or configuration such as `payload`.
- `L232-L244`: Attempts a potentially fragile operation and relies on later branches to handle failures safely.
- `L246-L264`: Implements this section of logic starting with `# Process the verified event`.
- `L267-L269`: Comment block that explains the next section: ---------------------------------------------------------------------------.
- `L271-L274`: Registers the `get_stripe_plans` endpoint with the API router.
- `L276-L282`: Implements this section of logic starting with `This endpoint does not require authentication so the pricing page can`.
- `L284-L288`: Implements this section of logic starting with `# Calculate yearly discount safely (avoid division by zero for free tier)`.
- `L290-L300`: Implements this section of logic starting with `plans.append({`.
- `L302`: Returns a value from the current function.
- `L305-L307`: Comment block that explains the next section: ---------------------------------------------------------------------------.
- `L309-L318`: Registers the `create_portal_session` endpoint with the API router.
- `L320-L329`: Implements this section of logic starting with `The portal allows customers to manage their subscription, update`.
- `L331-L336`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L338-L344`: Initializes module-level state or configuration such as `customer_id`.
- `L346-L358`: Attempts a potentially fragile operation and relies on later branches to handle failures safely.
- `L361-L363`: Comment block that explains the next section: ---------------------------------------------------------------------------.
- `L365-L371`: Registers the `get_subscription_status` endpoint with the API router.
- `L373-L376`: Implements this section of logic starting with `Checks the local database first. Returns plan details, billing cycle,`.
- `L378-L384`: Initializes module-level state or configuration such as `subscription`.
- `L386-L392`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L394-L411`: Returns a value from the current function.
