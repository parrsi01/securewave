# `backend/services/traffic_shaper.py`

Purpose: This backend service module manages low-level traffic shaper behavior for the VPN stack.

## Line Walkthrough

- `L1`: Module or block docstring that describes the responsibility of this section.
- `L3-L5`: Implements this section of logic starting with `This backend service module manages low-level traffic shaper behavior for the VPN stack.`.
- `L7-L13`: Imports the dependencies used later in this module, including __future__, json, os, subprocess, threading, time, pathlib.
- `L15`: Imports the dependencies used later in this module, including backend.
- `L17-L18`: Initializes module-level state or configuration such as `_PROTO_IFACE, _TBF_HANDLE`.
- `L21-L29`: Defines the `TrafficShaper` class and the behavior it groups together.
- `L31-L35`: Defines the `_load` function and the logic it executes.
- `L37-L40`: Defines the `_save` function and the logic it executes.
- `L42-L44`: Applies decorators and defines `_run` with the wrapped behavior declared above it.
- `L46-L62`: Applies decorators and defines `_used_today_bytes` with the wrapped behavior declared above it.
- `L64-L70`: Defines the `_iface_for` function and the logic it executes.
- `L72-L77`: Defines the `_root_qdisc` function and the logic it executes.
- `L79-L80`: Defines the `_is_default_root` function and the logic it executes.
- `L82-L92`: Defines the `_apply_free_tbf` function and the logic it executes.
- `L94-L97`: Defines the `_remove_free_tbf` function and the logic it executes.
- `L99-L120`: Defines the `apply_for_session` function and the logic it executes.
- `L122-L133`: Defines the `remove_for_session` function and the logic it executes.
- `L136`: Initializes module-level variables and configuration used by later code.
- `L139-L143`: Defines the `get_traffic_shaper` function and the logic it executes.
