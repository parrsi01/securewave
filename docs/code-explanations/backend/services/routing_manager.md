# `backend/services/routing_manager.py`

Purpose: This backend service module manages low-level routing manager behavior for the VPN stack.

## Line Walkthrough

- `L1`: Module or block docstring that describes the responsibility of this section.
- `L3-L5`: Implements this section of logic starting with `This backend service module manages low-level routing manager behavior for the VPN stack.`.
- `L7-L13`: Imports the dependencies used later in this module, including __future__, contextlib, fcntl, logging, subprocess, time, pathlib.
- `L15-L23`: Initializes module-level state or configuration such as `logger, _LOCK_PATH, _LOCK_TIMEOUT_SECONDS, _RT_TABLES, _CONFIG`.
- `L26-L28`: Defines the `_run` function and the logic it executes.
- `L31-L47`: Applies decorators and defines `network_lock` with the wrapped behavior declared above it.
- `L50-L71`: Defines the `_ensure_rt_table` function and the logic it executes.
- `L74-L76`: Defines the `_has_ip_rule` function and the logic it executes.
- `L79-L82`: Defines the `_main_default_iface` function and the logic it executes.
- `L85-L87`: Defines the `_table_default_uses_iface` function and the logic it executes.
- `L90-L103`: Defines the `setup_protocol` function and the logic it executes.
- `L106-L114`: Defines the `teardown_protocol` function and the logic it executes.
