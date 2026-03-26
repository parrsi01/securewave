# `services/wireguard_service.py`

Purpose: This service module implements the business logic for wireguard service operations.

## Line Walkthrough

- `L1`: Module or block docstring that describes the responsibility of this section.
- `L3-L5`: Implements this section of logic starting with `This service module implements the business logic for wireguard service operations.`.
- `L7-L15`: Imports the dependencies used later in this module, including base64, logging, shutil, stat, subprocess  # nosec B404 - controlled subprocess usage, ipaddress, io, pathlib, ....
- `L17-L25`: Implements this section of logic starting with `import qrcode`.
- `L27-L28`: Imports the dependencies used later in this module, including config, utils.
- `L30-L31`: Imports the dependencies used later in this module, including models, services.
- `L33-L34`: Initializes module-level state or configuration such as `logger, SETTINGS`.
- `L37-L58`: Defines the `WireGuardService` class and the behavior it groups together.
- `L60-L68`: Defines the `_load_fernet` function and the logic it executes.
- `L70-L79`: Defines the `generate_keypair` function and the logic it executes.
- `L81-L87`: Implements this section of logic starting with `# WireGuard keys are Curve25519 (X25519) keys, base64-encoded.`.
- `L89-L95`: Defines the `encrypt_private_key` function and the logic it executes.
- `L97-L105`: Defines the `decrypt_private_key` function and the logic it executes.
- `L107-L109`: Applies decorators and defines `_write_secret_file` with the wrapped behavior declared above it.
- `L111-L122`: Implements this section of logic starting with `L-9: WireGuard client config files contain the peer PrivateKey in plaintext.`.
- `L124-L131`: Defines the `ensure_server_keys` function and the logic it executes.
- `L133-L135`: Defines the `allocate_ip` function and the logic it executes.
- `L137-L147`: Implements this section of logic starting with `NOTE:`.
- `L149-L153`: Initializes module-level state or configuration such as `reserved_hosts, usable_per_block, idx, block_offset, host_offset`.
- `L155-L158`: Initializes module-level state or configuration such as `block_start, block_network, host_int`.
- `L160-L167`: Defines the `generate_client_config` function and the logic it executes.
- `L169-L170`: Initializes module-level state or configuration such as `client_ip, server_public_key`.
- `L172-L192`: Initializes module-level state or configuration such as `tuning, endpoint, client_ip, forwarded_for, observed_latency_ms, device_type`.
- `L194-L196`: Initializes module-level state or configuration such as `config_path`.
- `L198-L199`: Defines the `config_exists` function and the logic it executes.
- `L201-L202`: Defines the `config_path_for_server` function and the logic it executes.
- `L204-L205`: Defines the `config_exists_for_server` function and the logic it executes.
- `L207-L211`: Defines the `get_config` function and the logic it executes.
- `L213-L217`: Defines the `get_config_for_server` function and the logic it executes.
- `L219-L221`: Defines the `generate_client_config_for_server` function and the logic it executes.
- `L223-L225`: Implements this section of logic starting with `Args:`.
- `L227-L237`: Implements this section of logic starting with `Returns:`.
- `L239`: Initializes module-level state or configuration such as `client_ip`.
- `L241-L262`: Implements this section of logic starting with `# Use server-specific endpoint and public key; apply adaptive tuning.`.
- `L264-L267`: Implements this section of logic starting with `# Save config with server_id in filename`.
- `L269-L273`: Defines the `qr_from_config` function and the logic it executes.
