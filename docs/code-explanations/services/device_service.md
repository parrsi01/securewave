# `services/device_service.py`

Purpose: This service module implements the business logic for device service operations.

## Line Walkthrough

- `L1`: Module or block docstring that describes the responsibility of this section.
- `L3-L5`: Implements this section of logic starting with `This service module implements the business logic for device service operations.`.
- `L7`: Imports the dependencies used later in this module, including __future__.
- `L9-L12`: Imports the dependencies used later in this module, including logging, dataclasses, datetime, typing.
- `L14`: Imports the dependencies used later in this module, including sqlalchemy.
- `L16-L29`: Implements this section of logic starting with `from models.vpn_credential import VPNCredential`.
- `L31`: Initializes module-level state or configuration such as `logger`.
- `L34-L36`: Applies decorators and defines `DeviceCleanupSummary` with the wrapped behavior declared above it.
- `L38-L39`: Defines the `to_dict` function and the logic it executes.
- `L42-L43`: Defines `DeviceService`. Centralize device lifecycle updates and remote peer cleanup.
- `L45-L46`: Defines the `__init__` function and the logic it executes.
- `L48-L54`: Applies decorators and defines `_to_naive_utc` with the wrapped behavior declared above it.
- `L56-L70`: Defines the `_set_state` function and the logic it executes.
- `L72-L88`: Defines the `mark_profile_issued` function and the logic it executes.
- `L90-L105`: Defines the `mark_expired` function and the logic it executes.
- `L107-L122`: Defines the `expire_if_due` function and the logic it executes.
- `L124-L148`: Defines the `expire_due_devices` function and the logic it executes.
- `L150-L164`: Defines the `remove_remote_peer` function and the logic it executes.
- `L166-L229`: Defines the `revoke_credentials_for_device` function and the logic it executes.
- `L231-L256`: Defines the `revoke_device` function and the logic it executes.
- `L258-L278`: Defines the `delete_device` function and the logic it executes.
- `L281-L282`: Defines the `get_device_service` function and the logic it executes.
