# `services/geo_recommendation.py`

Purpose: This service module implements the business logic for geo recommendation operations.

## Line Walkthrough

- `L1-L2`: Module or block docstring that describes the responsibility of this section.
- `L4-L5`: Implements this section of logic starting with `Used by:`.
- `L7-L11`: Implements this section of logic starting with `Inputs:`.
- `L13`: Imports the dependencies used later in this module, including __future__.
- `L15-L20`: Imports the dependencies used later in this module, including json, os, dataclasses, datetime, pathlib, typing.
- `L22`: Imports the dependencies used later in this module, including sqlalchemy.
- `L24-L27`: Imports the dependencies used later in this module, including models, services.
- `L30-L31`: Defines the `_utc_now_iso` function and the logic it executes.
- `L34-L38`: Defines the `_env_bool` function and the logic it executes.
- `L41-L45`: Defines the `_safe_float` function and the logic it executes.
- `L48-L54`: Applies decorators and defines `GeoRecoBaselines` with the wrapped behavior declared above it.
- `L56-L61`: Defines the `as_latency_optimizer_baselines` function and the logic it executes.
- `L64-L74`: Applies decorators and defines `ScoredServer` with the wrapped behavior declared above it.
- `L77-L86`: Defines the `_load_geo_latency_report` function and the logic it executes.
- `L89-L92`: Defines the `_baselines_from_geo_report` function and the logic it executes.
- `L94-L106`: Initializes module-level state or configuration such as `barbados, europe`.
- `L108-L109`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L111-L117`: Returns a value from the current function.
- `L120-L123`: Defines the `_fallback_baselines` function and the logic it executes.
- `L126-L131`: Defines the `_has_explicit_env_baselines` function and the logic it executes.
- `L134-L138`: Defines the `load_baselines` function and the logic it executes.
- `L140-L148`: Initializes module-level state or configuration such as `report_path, report`.
- `L151-L154`: Defines `_ServerView`. Minimal view for GeoLatencyOptimizer.score_server().
- `L156-L160`: Defines the `__init__` function and the logic it executes.
- `L163-L175`: Defines the `_score_server` function and the logic it executes.
- `L177-L179`: Initializes module-level state or configuration such as `load_percent, consecutive_failures, health`.
- `L181-L185`: Initializes module-level state or configuration such as `health_penalty`.
- `L187-L188`: Implements this section of logic starting with `# Prefer lower load; keep the penalty modest so latency doesn't get ignored.`.
- `L190-L191`: Implements this section of logic starting with `# Recent failures are a strong negative signal.`.
- `L193`: Returns a value from the current function.
- `L196-L204`: Defines the `recommend_server` function and the logic it executes.
- `L206-L207`: Initializes module-level state or configuration such as `window_seconds, min_samples`.
- `L209-L210`: Initializes module-level state or configuration such as `servers`.
- `L212-L215`: Loops over a collection to apply the same work to each item.
- `L217-L222`: Initializes module-level state or configuration such as `vpn_server_id, window_seconds, min_samples`.
- `L224-L231`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L233-L238`: Initializes module-level state or configuration such as `score, rtt_ms, baselines, user_region_hint`.
- `L240-L253`: Initializes module-level state or configuration such as `load_percent, server_id, score, rtt_ms, rtt_source, rtt_samples`.
- `L255-L256`: Initializes module-level state or configuration such as `recommended_id`.
- `L258-L267`: Initializes module-level variables and configuration used by later code.
- `L269-L270`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L272`: Returns a value from the current function.
- `L275-L279`: Defines the `_atomic_write` function and the logic it executes.
- `L282-L284`: Defines the `_write_geo_reco_artifacts` function and the logic it executes.
- `L286`: Initializes module-level state or configuration such as `indent`.
- `L288-L321`: Implements this section of logic starting with `# Compact CSV for quick diffing in CI.`.
