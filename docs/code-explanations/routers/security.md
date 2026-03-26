# `routers/security.py`

Purpose: This module exposes API handlers for security features in the SecureWave backend.

## Line Walkthrough

- `L1-L2`: Module or block docstring that describes the responsibility of this section.
- `L4-L8`: Implements this section of logic starting with `Exposes the SecurityMonitor capabilities as HTTP endpoints:`.
- `L10`: Imports the dependencies used later in this module, including typing.
- `L12-L14`: Imports the dependencies used later in this module, including fastapi, pydantic, sqlalchemy.
- `L16-L19`: Imports the dependencies used later in this module, including database, models, services.
- `L21`: Initializes module-level state or configuration such as `router`.
- `L24-L26`: Comment block that explains the next section: ---------------------------------------------------------------------------.
- `L28-L35`: Defines `_require_admin`. Raise 403 if the authenticated user is not an admin.
- `L38-L40`: Comment block that explains the next section: ---------------------------------------------------------------------------.
- `L42-L59`: Defines `SuspiciousActivityReport`. Body for POST /api/security/report.
- `L62-L64`: Comment block that explains the next section: ---------------------------------------------------------------------------.
- `L66-L79`: Registers the `security_status` endpoint with the API router.
- `L82-L88`: Registers the `security_alerts` endpoint with the API router.
- `L90-L96`: Implements this section of logic starting with `Query parameters:`.
- `L98-L106`: Initializes module-level state or configuration such as `monitor, alerts, summary`.
- `L109-L125`: Registers the `report_suspicious_activity` endpoint with the API router.
