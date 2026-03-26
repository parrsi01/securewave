# `models/user.py`

Purpose: This module defines the database model for user records used by SecureWave.

## Line Walkthrough

- `L1`: Module or block docstring that describes the responsibility of this section.
- `L3-L5`: Implements this section of logic starting with `This module defines the database model for user records used by SecureWave.`.
- `L7`: Imports the dependencies used later in this module, including datetime.
- `L9-L10`: Imports the dependencies used later in this module, including sqlalchemy.
- `L12-L13`: Imports the dependencies used later in this module, including database, utils.
- `L16-L17`: Defines the `User` class and the behavior it groups together.
- `L19-L24`: Initializes module-level state or configuration such as `id, email, hashed_password, created_at, is_active, is_admin`.
- `L26-L29`: Implements this section of logic starting with `# VPN Keys`.
- `L31-L34`: Implements this section of logic starting with `# Legacy subscription fields (deprecated - use Subscription model instead)`.
- `L36-L39`: Implements this section of logic starting with `# Email verification`.
- `L41-L44`: Implements this section of logic starting with `# Password reset`.
- `L46-L49`: Implements this section of logic starting with `# Two-Factor Authentication (TOTP)`.
- `L51-L55`: Implements this section of logic starting with `# Security tracking`.
- `L57-L58`: Implements this section of logic starting with `# Relationships`.
- `L60-L65`: Applies decorators and defines `is_locked` with the wrapped behavior declared above it.
- `L67-L70`: Applies decorators and defines `requires_email_verification` with the wrapped behavior declared above it.
- `L72-L75`: Applies decorators and defines `has_2fa_enabled` with the wrapped behavior declared above it.
