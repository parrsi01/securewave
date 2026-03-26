# `backend/services/wireguard_service.py`

Purpose: This backend service module manages low-level wireguard service behavior for the VPN stack.

## Line Walkthrough

- `L1`: Module or block docstring that describes the responsibility of this section.
- `L3-L5`: Implements this section of logic starting with `This backend service module manages low-level wireguard service behavior for the VPN stack.`.
- `L7`: Imports the dependencies used later in this module, including __future__.
- `L9-L10`: Imports the dependencies used later in this module, including os, subprocess.
- `L12-L15`: Imports the dependencies used later in this module, including backend.
- `L18-L24`: Defines the `WireGuardService` class and the behavior it groups together.
- `L26-L28`: Applies decorators and defines `_run` with the wrapped behavior declared above it.
- `L30-L44`: Applies decorators and defines `_detect_egress_iface` with the wrapped behavior declared above it.
- `L46-L49`: Defines the `setup_network_state` function and the logic it executes.
- `L51-L55`: Defines the `teardown_network_state` function and the logic it executes.
- `L57-L58`: Defines the `setup_nat_isolation` function and the logic it executes.
- `L60-L61`: Defines the `teardown_nat_isolation` function and the logic it executes.
- `L63-L68`: Defines the `start_meter` function and the logic it executes.
- `L70-L77`: Defines the `stop_meter` function and the logic it executes.
- `L79-L80`: Defines the `apply_shaping` function and the logic it executes.
- `L82-L83`: Defines the `remove_shaping` function and the logic it executes.
