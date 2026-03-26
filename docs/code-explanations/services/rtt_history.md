# `services/rtt_history.py`

Purpose: This service module implements the business logic for rtt history operations.

## Line Walkthrough

- `L1-L2`: Module or block docstring that describes the responsibility of this section.
- `L4-L6`: Implements this section of logic starting with `This is used by Barbados/EU recommendation scoring to incorporate recent`.
- `L8`: Imports the dependencies used later in this module, including __future__.
- `L10-L14`: Imports the dependencies used later in this module, including os, dataclasses, datetime, statistics, typing.
- `L16`: Imports the dependencies used later in this module, including sqlalchemy.
- `L18`: Imports the dependencies used later in this module, including models.
- `L21-L26`: Defines the `_env_int` function and the logic it executes.
- `L29-L38`: Defines the `_percentile` function and the logic it executes.
- `L41-L48`: Applies decorators and defines `RTTRollup` with the wrapped behavior declared above it.
- `L51-L59`: Defines the `record_rtt_sample` function and the logic it executes.
- `L61-L65`: Implements this section of logic starting with `TTL defaults to 6 hours and can be overridden with:`.
- `L67-L73`: Implements this section of logic starting with `db.add(`.
- `L75-L79`: Implements this section of logic starting with `# Best-effort cleanup to keep the table bounded.`.
- `L82-L90`: Defines the `get_rtt_rollup` function and the logic it executes.
- `L92-L108`: Implements this section of logic starting with `Returns None if there are fewer than min_samples samples in the window.`.
- `L110-L117`: Returns a value from the current function.
