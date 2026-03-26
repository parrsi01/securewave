# `backend/services/plan_manager.py`

Purpose: This backend service module manages low-level plan manager behavior for the VPN stack.

## Line Walkthrough

- `L1`: Module or block docstring that describes the responsibility of this section.
- `L3-L5`: Implements this section of logic starting with `This backend service module manages low-level plan manager behavior for the VPN stack.`.
- `L7`: Imports the dependencies used later in this module, including __future__.
- `L9`: Imports the dependencies used later in this module, including dataclasses.
- `L11-L12`: Initializes module-level state or configuration such as `_FREE, _PREMIUM`.
- `L15-L20`: Applies decorators and defines `PlanDecision` with the wrapped behavior declared above it.
- `L23-L31`: Defines the `PlanManager` class and the behavior it groups together.
- `L33-L40`: Defines the `resolve` function and the logic it executes.
- `L43`: Initializes module-level variables and configuration used by later code.
- `L46-L50`: Defines the `get_plan_manager` function and the logic it executes.
