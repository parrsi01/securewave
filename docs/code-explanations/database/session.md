# `database/session.py`

Purpose: This database module configures session support for the SecureWave backend.

## Line Walkthrough

- `L1`: Module or block docstring that describes the responsibility of this section.
- `L3-L5`: Implements this section of logic starting with `This database module configures session support for the SecureWave backend.`.
- `L7-L10`: Imports the dependencies used later in this module, including os, logging, tempfile, typing.
- `L12-L14`: Imports the dependencies used later in this module, including sqlalchemy.
- `L16`: Imports the dependencies used later in this module, including config.
- `L18-L19`: Initializes module-level state or configuration such as `logger, SETTINGS`.
- `L21-L22`: Implements this section of logic starting with `# Database configuration`.
- `L24-L29`: Implements this section of logic starting with `# Connection pool settings (production-grade)`.
- `L31-L33`: Implements this section of logic starting with `# Environment`.
- `L35-L41`: Implements this section of logic starting with `# Engine configuration`.
- `L43-L46`: Implements this section of logic starting with `# Configure based on database type`.
- `L48-L49`: Implements this section of logic starting with `# Extract the path after sqlite:///`.
- `L51-L56`: Implements this section of logic starting with `# Ensure production SQLite uses persistent storage`.
- `L58-L66`: Implements this section of logic starting with `# Preserve in-memory SQLite for tests/dev`.
- `L68-L77`: Implements this section of logic starting with `# Ensure directory exists`.
- `L79-L85`: Implements this section of logic starting with `# SQLite-specific settings`.
- `L87`: Initializes module-level state or configuration such as `engine`.
- `L89-L91`: Continues the conditional branch for the surrounding decision tree.
- `L93-L100`: Implements this section of logic starting with `# PostgreSQL-specific settings`.
- `L102-L108`: Implements this section of logic starting with `# SSL/TLS configuration for PostgreSQL in production`.
- `L110-L111`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L113`: Initializes module-level state or configuration such as `engine`.
- `L115-L120`: Implements this section of logic starting with `# Log connection pool info`.
- `L122-L124`: Provides the fallback branch when earlier conditions are not met.
- `L126-L130`: Implements this section of logic starting with `# Production event handlers`.
- `L132-L144`: Implements this section of logic starting with `# Set PostgreSQL-specific settings for each connection`.
- `L147-L150`: Applies decorators and defines `receive_checkout` with the wrapped behavior declared above it.
- `L153-L156`: Applies decorators and defines `receive_checkin` with the wrapped behavior declared above it.
- `L159-L160`: Implements this section of logic starting with `# Session factory`.
- `L163-L165`: Defines the `get_db` function and the logic it executes.
- `L167-L168`: Implements this section of logic starting with `Yields:`.
- `L170-L183`: Implements this section of logic starting with `Usage:`.
- `L186-L210`: Defines `create_tables`. Create all database tables.
- `L212-L219`: Implements this section of logic starting with `logger.info("Creating database tables...")`.
- `L222-L224`: Defines the `_ensure_sqlite_compat_columns` function and the logic it executes.
- `L226-L231`: Implements this section of logic starting with ``create_all()` creates missing tables but does not alter old ones. Production`.
- `L233-L241`: Initializes module-level state or configuration such as `compat_columns`.
- `L243-L255`: Initializes module-level state or configuration such as `inspector`.
- `L258-L260`: Defines the `check_database_connection` function and the logic it executes.
- `L262-L274`: Implements this section of logic starting with `Returns:`.
- `L277-L279`: Defines the `get_database_info` function and the logic it executes.
- `L281-L291`: Implements this section of logic starting with `Returns:`.
- `L293-L304`: Attempts a potentially fragile operation and relies on later branches to handle failures safely.
- `L306`: Returns a value from the current function.
- `L309-L314`: Implements this section of logic starting with `# Initialize database on import (development only)`.
- `L317-L325`: Implements this section of logic starting with `# Export commonly used items`.
