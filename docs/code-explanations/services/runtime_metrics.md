# `services/runtime_metrics.py`

Purpose: This service module implements the business logic for runtime metrics operations.

## Line Walkthrough

- `L1-L3`: Module or block docstring that describes the responsibility of this section.
- `L5`: Imports the dependencies used later in this module, including __future__.
- `L7-L11`: Imports the dependencies used later in this module, including threading, time, collections, statistics, typing.
- `L13`: Imports the dependencies used later in this module, including psutil.
- `L16-L25`: Defines the `_percentile` function and the logic it executes.
- `L28-L44`: Defines the `RuntimeMetrics` class and the behavior it groups together.
- `L46-L52`: Defines the `record_profile_issue` function and the logic it executes.
- `L54-L56`: Defines the `record_peer_connect` function and the logic it executes.
- `L58-L60`: Defines the `record_peer_disconnect` function and the logic it executes.
- `L62-L64`: Defines the `record_failed_auth` function and the logic it executes.
- `L66-L68`: Defines the `record_rate_limited` function and the logic it executes.
- `L70-L73`: Defines the `record_handshake_latency` function and the logic it executes.
- `L75-L80`: Defines the `record_region_resolution` function and the logic it executes.
- `L82-L84`: Defines the `record_region_circuit_open` function and the logic it executes.
- `L86-L102`: Defines the `_latency_stats` function and the logic it executes.
- `L104-L118`: Defines the `snapshot` function and the logic it executes.
- `L120-L123`: Initializes module-level state or configuration such as `vm, cpu_percent, proc, process_memory_mb`.
- `L125`: Initializes module-level state or configuration such as `extended`.
- `L127-L138`: Returns a value from the current function.
- `L140-L142`: Defines the `_extended_system_snapshot` function and the logic it executes.
- `L144-L150`: Implements this section of logic starting with `This keeps Prometheus scrapes cheap while still surfacing FD/thread`.
- `L152-L156`: Initializes module-level variables and configuration used by later code.
- `L158-L161`: Attempts a potentially fragile operation and relies on later branches to handle failures safely.
- `L163-L170`: Initializes module-level state or configuration such as `wg_processes, zombie_processes`.
- `L172-L173`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L175-L182`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L184-L189`: Initializes module-level state or configuration such as `extended`.
- `L191-L194`: Opens a managed context so resources are cleaned up automatically after use.
- `L196-L201`: Defines the `export_prometheus` function and the logic it executes.
- `L203-L255`: Initializes module-level state or configuration such as `lines`.
- `L257-L277`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L279`: Returns a value from the current function.
- `L282`: Initializes module-level variables and configuration used by later code.
- `L285-L289`: Defines the `get_runtime_metrics` function and the logic it executes.
