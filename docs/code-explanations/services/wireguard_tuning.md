# `services/wireguard_tuning.py`

Purpose: This service module implements the business logic for wireguard tuning operations.

## Line Walkthrough

- `L1-L3`: Module or block docstring that describes the responsibility of this section.
- `L5`: Imports the dependencies used later in this module, including __future__.
- `L7-L14`: Imports the dependencies used later in this module, including ipaddress, os, shutil, socket, subprocess  # nosec B404 - controlled local probe, time, dataclasses, typing.
- `L17-L22`: Applies decorators and defines `WireGuardTuning` with the wrapped behavior declared above it.
- `L25-L30`: Defines the `_int_env` function and the logic it executes.
- `L33-L37`: Defines the `_bool_env` function and the logic it executes.
- `L40-L44`: Defines the `detect_nat` function and the logic it executes.
- `L46-L55`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L57-L60`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L63-L66`: Defines the `_probe_mtu` function and the logic it executes.
- `L68-L88`: Initializes module-level state or configuration such as `start`.
- `L90`: Returns a value from the current function.
- `L93-L100`: Defines the `_host_from_endpoint` function and the logic it executes.
- `L103-L111`: Defines the `_is_ipv6_host` function and the logic it executes.
- `L114-L126`: Defines the `tune_wireguard` function and the logic it executes.
- `L128-L131`: Initializes module-level state or configuration such as `nat_detected`.
- `L133-L141`: Initializes module-level state or configuration such as `forced_mtu_raw`.
- `L143-L150`: Initializes module-level state or configuration such as `mtu_probe_ms, mtu`.
- `L152-L158`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L160-L175`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L177-L180`: Initializes module-level state or configuration such as `keepalive_nat, keepalive_public, keepalive_seconds`.
- `L182-L187`: Returns a value from the current function.
