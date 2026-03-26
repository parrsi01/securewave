# `services/tunnel_runtime.py`

Purpose: This service module implements the business logic for tunnel runtime operations.

## Line Walkthrough

- `L1-L2`: Module or block docstring that describes the responsibility of this section.
- `L4-L6`: Implements this section of logic starting with `The simulated runtime is deterministic, in-memory, and never touches OS`.
- `L8`: Imports the dependencies used later in this module, including __future__.
- `L10-L15`: Imports the dependencies used later in this module, including os, threading, time, uuid, dataclasses, typing.
- `L17`: Imports the dependencies used later in this module, including utils.
- `L20`: Initializes module-level state or configuration such as `TunnelMode`.
- `L23-L28`: Applies decorators and defines `TunnelConnectResult` with the wrapped behavior declared above it.
- `L31-L39`: Applies decorators and defines `TunnelTrafficStats` with the wrapped behavior declared above it.
- `L42-L46`: Applies decorators and defines `TunnelTrafficDelta` with the wrapped behavior declared above it.
- `L49-L50`: Defines `TunnelRuntime`. Interface for runtime connect/disconnect and traffic accounting.
- `L52`: Initializes module-level variables and configuration used by later code.
- `L54-L62`: Defines the `connect` function and the logic it executes.
- `L64-L65`: Defines the `disconnect` function and the logic it executes.
- `L67-L68`: Defines the `get_traffic` function and the logic it executes.
- `L70-L71`: Defines the `pop_traffic_delta` function and the logic it executes.
- `L73-L74`: Defines the `health` function and the logic it executes.
- `L76-L77`: Defines the `active_session_for_user` function and the logic it executes.
- `L80-L82`: Defines the `RealTunnelRuntime` class and the behavior it groups together.
- `L84-L86`: Implements this section of logic starting with `Real tunnel operations are still handled by existing runtime paths. This`.
- `L88`: Initializes module-level variables and configuration used by later code.
- `L90-L93`: Defines the `__init__` function and the logic it executes.
- `L95-L122`: Defines the `connect` function and the logic it executes.
- `L124-L132`: Defines the `disconnect` function and the logic it executes.
- `L134-L153`: Defines the `get_traffic` function and the logic it executes.
- `L155-L174`: Defines the `pop_traffic_delta` function and the logic it executes.
- `L176-L179`: Defines the `health` function and the logic it executes.
- `L181-L183`: Defines the `active_session_for_user` function and the logic it executes.
- `L186-L189`: Defines `SimulatedTunnelRuntime`. Deterministic in-memory runtime for dev/test.
- `L191`: Initializes module-level variables and configuration used by later code.
- `L193-L201`: Defines the `__init__` function and the logic it executes.
- `L203-L212`: Defines the `_tick_locked` function and the logic it executes.
- `L214-L223`: Defines the `connect` function and the logic it executes.
- `L225-L243`: Opens a managed context so resources are cleaned up automatically after use.
- `L245-L247`: Initializes module-level state or configuration such as `old`.
- `L249-L266`: Initializes module-level state or configuration such as `session_id, now_mono`.
- `L268-L278`: Defines the `disconnect` function and the logic it executes.
- `L280-L300`: Defines the `get_traffic` function and the logic it executes.
- `L302-L322`: Defines the `pop_traffic_delta` function and the logic it executes.
- `L324-L333`: Defines the `health` function and the logic it executes.
- `L335-L337`: Defines the `active_session_for_user` function and the logic it executes.
- `L339-L349`: Defines the `set_traffic_rate` function and the logic it executes.
- `L351-L359`: Defines the `inject_traffic` function and the logic it executes.
- `L361-L378`: Defines the `set_failure_modes` function and the logic it executes.
- `L381-L383`: Initializes module-level state or configuration such as `_RUNTIME_LOCK`.
- `L386-L390`: Defines the `_bool_env` function and the logic it executes.
- `L393-L409`: Defines the `ensure_tunnel_mode_allowed` function and the logic it executes.
- `L412-L413`: Defines the `tunnel_mode` function and the logic it executes.
- `L416-L417`: Defines the `is_simulated_tunnel_mode` function and the logic it executes.
- `L420-L432`: Defines the `get_tunnel_runtime` function and the logic it executes.
- `L435-L439`: Defines the `reset_tunnel_runtime_for_tests` function and the logic it executes.
