# `backend/services/ikev2_service.py`

Purpose: This backend service module manages low-level ikev2 service behavior for the VPN stack.

## Line Walkthrough

- `L1`: Module or block docstring that describes the responsibility of this section.
- `L3-L5`: Implements this section of logic starting with `This backend service module manages low-level ikev2 service behavior for the VPN stack.`.
- `L7`: Imports the dependencies used later in this module, including __future__.
- `L9-L11`: Imports the dependencies used later in this module, including os, re, subprocess.
- `L13-L16`: Imports the dependencies used later in this module, including backend.
- `L19-L25`: Defines the `IKEv2Service` class and the behavior it groups together.
- `L27-L35`: Applies decorators and defines `_run` with the wrapped behavior declared above it.
- `L37-L45`: Applies decorators and defines `_detect_egress_iface` with the wrapped behavior declared above it.
- `L47-L49`: Defines the `_mark_token` function and the logic it executes.
- `L51-L52`: Defines the `_iface_exists` function and the logic it executes.
- `L54-L80`: Defines the `_cleanup_xfrm_states` function and the logic it executes.
- `L82-L95`: Defines the `_cleanup_xfrm_policies` function and the logic it executes.
- `L97-L100`: Defines the `setup_network_state` function and the logic it executes.
- `L102-L109`: Defines the `teardown_network_state` function and the logic it executes.
- `L111-L112`: Defines the `setup_nat_isolation` function and the logic it executes.
- `L114-L115`: Defines the `teardown_nat_isolation` function and the logic it executes.
- `L117-L120`: Defines the `start_meter` function and the logic it executes.
- `L122-L123`: Defines the `stop_meter` function and the logic it executes.
- `L125-L126`: Defines the `apply_shaping` function and the logic it executes.
- `L128-L129`: Defines the `remove_shaping` function and the logic it executes.
