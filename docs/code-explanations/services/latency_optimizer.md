# `services/latency_optimizer.py`

Purpose: This service module implements the business logic for latency optimizer operations.

## Line Walkthrough

- `L1-L3`: Module or block docstring that describes the responsibility of this section.
- `L5`: Imports the dependencies used later in this module, including __future__.
- `L7-L12`: Imports the dependencies used later in this module, including os, shutil, subprocess  # nosec B404 - controlled local ping, time, dataclasses, typing.
- `L15-L19`: Applies decorators and defines `BaselineLatency` with the wrapped behavior declared above it.
- `L22-L26`: Applies decorators and defines `ScoredServer` with the wrapped behavior declared above it.
- `L29-L34`: Defines the `_default_float` function and the logic it executes.
- `L37-L40`: Defines the `_ping_latency_ms` function and the logic it executes.
- `L42-L49`: Initializes module-level state or configuration such as `start, cmd`.
- `L51-L60`: Implements this section of logic starting with `# Parse avg latency from ping output if available.`.
- `L62`: Returns a value from the current function.
- `L65-L68`: Defines the `GeoLatencyOptimizer` class and the behavior it groups together.
- `L70-L72`: Defines the `collect_baselines` function and the logic it executes.
- `L74-L79`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L81-L85`: Returns a value from the current function.
- `L87-L95`: Defines the `score_server` function and the logic it executes.
- `L97-L99`: Implements this section of logic starting with `Higher score is better.`.
- `L101-L103`: Initializes module-level state or configuration such as `region, latency_ms, performance_score`.
- `L105-L106`: Implements this section of logic starting with `# Base RTT preference: lower is better.`.
- `L108-L110`: Initializes module-level state or configuration such as `corridor_multiplier`.
- `L112-L114`: Implements this section of logic starting with `# Prefer low RTT corridor between Caribbean and EU by anchoring to both baselines.`.
- `L116-L120`: Initializes module-level state or configuration such as `region_hint`.
- `L122-L123`: Initializes module-level state or configuration such as `score`.
- `L125-L136`: Defines the `rank_servers` function and the logic it executes.
- `L139`: Initializes module-level variables and configuration used by later code.
- `L142-L146`: Defines the `get_latency_optimizer` function and the logic it executes.
