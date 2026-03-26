# `routes/vpn_metrics.py`

Purpose: This module exposes API handlers for vpn metrics features in the SecureWave backend.

## Line Walkthrough

- `L1-L2`: Module or block docstring that describes the responsibility of this section.
- `L4-L5`: Implements this section of logic starting with `Client-side metrics ingest and admin query endpoint.`.
- `L7-L9`: Imports the dependencies used later in this module, including logging, datetime, typing.
- `L11-L14`: Imports the dependencies used later in this module, including fastapi, pydantic, sqlalchemy.
- `L16-L19`: Imports the dependencies used later in this module, including database, models, services.
- `L21-L22`: Initializes module-level state or configuration such as `logger, router`.
- `L25-L27`: Comment block that explains the next section: ---------------------------------------------------------------------------.
- `L29-L36`: Defines the `MetricSubmission` class and the behavior it groups together.
- `L39-L41`: Comment block that explains the next section: ---------------------------------------------------------------------------.
- `L43-L63`: Registers the `submit_vpn_metric` endpoint with the API router.
- `L66-L68`: Comment block that explains the next section: ---------------------------------------------------------------------------.
- `L70-L73`: Defines the `_require_admin` function and the logic it executes.
- `L76-L84`: Registers the `get_vpn_metrics` endpoint with the API router.
- `L86-L89`: Implements this section of logic starting with `Returns per-server averages for handshake time, latency, packet loss,`.
- `L91-L101`: Initializes module-level state or configuration such as `query`.
- `L103-L104`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L106`: Initializes module-level state or configuration such as `rows`.
- `L108-L120`: Initializes module-level state or configuration such as `servers`.
- `L122-L125`: Returns a value from the current function.
