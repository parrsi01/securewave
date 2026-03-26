# `services/server_ranker.py`

Purpose: This service module implements the business logic for server ranker operations.

## Line Walkthrough

- `L1-L2`: Module or block docstring that describes the responsibility of this section.
- `L4`: Implements this section of logic starting with `Scores each candidate on three axes and returns them sorted best-first.`.
- `L6-L8`: Initializes module-level state or configuration such as `composite_score`.
- `L10`: Implements this section of logic starting with `Weights are configurable via environment variables.`.
- `L12-L13`: Implements this section of logic starting with `See docs/server_selection_algorithm.md for the full specification.`.
- `L15`: Imports the dependencies used later in this module, including __future__.
- `L17-L19`: Imports the dependencies used later in this module, including os, dataclasses, typing.
- `L21`: Imports the dependencies used later in this module, including models.
- `L24-L26`: Comment block that explains the next section: ---------------------------------------------------------------------------.
- `L28-L35`: Defines the `_env_float` function and the logic it executes.
- `L38-L40`: Initializes module-level state or configuration such as `W_LATENCY, W_LOAD, W_REGION`.
- `L42-L43`: Implements this section of logic starting with `# Latency beyond this value scores 0.`.
- `L45-L55`: Implements this section of logic starting with `# Region affinity mapping: region_hint → ordered list of preferred regions.`.
- `L58-L60`: Comment block that explains the next section: ---------------------------------------------------------------------------.
- `L63-L65`: Applies decorators and defines `RankedServer` with the wrapped behavior declared above it.
- `L67-L71`: Implements this section of logic starting with `server_id: str`.
- `L74-L80`: Defines the `rank_servers` function and the logic it executes.
- `L82-L84`: Implements this section of logic starting with `Args:`.
- `L86-L90`: Implements this section of logic starting with `Returns:`.
- `L92-L106`: Initializes module-level variables and configuration used by later code.
- `L108-L109`: Initializes module-level variables and configuration used by later code.
- `L112-L127`: Defines `select_best`. Convenience wrapper: returns the single best candidate, or ``None``.
- `L130-L132`: Comment block that explains the next section: ---------------------------------------------------------------------------.
- `L135-L137`: Defines the `_latency_score` function and the logic it executes.
- `L139-L148`: Implements this section of logic starting with ```latency_ms == 0`` maps to 1.0.`.
- `L151-L153`: Defines the `_load_score_inv` function and the logic it executes.
- `L155-L157`: Implements this section of logic starting with `Uses the precomputed ``VPNServer.load_score`` (0.0–1.0).`.
- `L160-L163`: Defines the `_region_score` function and the logic it executes.
- `L165-L168`: Implements this section of logic starting with `When *region_hint* is ``None``, all servers score 0.5 (neutral).`.
- `L170-L173`: Initializes module-level state or configuration such as `hint, preferred`.
- `L175-L179`: Initializes module-level state or configuration such as `server_region`.
- `L181`: Returns a value from the current function.
