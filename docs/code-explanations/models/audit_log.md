# `models/audit_log.py`

Purpose: This module defines the database model for audit log records used by SecureWave.

## Line Walkthrough

- `L1-L3`: Module or block docstring that describes the responsibility of this section.
- `L5-L8`: Imports the dependencies used later in this module, including datetime, typing, sqlalchemy.
- `L10-L11`: Imports the dependencies used later in this module, including database, utils.
- `L14-L19`: Defines `AuditLog`. Audit Log - Track all security-relevant events Immutable records for compliance and security investigations.
- `L21`: Initializes module-level state or configuration such as `id`.
- `L23-L26`: Implements this section of logic starting with `# Event identification`.
- `L28-L31`: Implements this section of logic starting with `# Actor information`.
- `L33-L36`: Implements this section of logic starting with `# Resource affected`.
- `L38-L40`: Implements this section of logic starting with `# Event details`.
- `L42-L45`: Implements this section of logic starting with `# Request metadata`.
- `L47-L50`: Implements this section of logic starting with `# Security flags`.
- `L52-L54`: Implements this section of logic starting with `# Result`.
- `L56-L59`: Implements this section of logic starting with `# Backward compatibility`.
- `L61-L62`: Implements this section of logic starting with `# Timestamp (immutable)`.
- `L64-L65`: Implements this section of logic starting with `# Relationships`.
- `L67-L74`: Implements this section of logic starting with `# Table arguments for composite indexes`.
- `L76-L77`: Defines the `__repr__` function and the logic it executes.
- `L79-L100`: Defines `to_dict`. Convert to dictionary.
- `L103-L107`: Defines `PerformanceMetric`. Performance Metrics - Track application performance.
- `L109`: Initializes module-level state or configuration such as `id`.
- `L111-L113`: Implements this section of logic starting with `# Metric identification`.
- `L115-L119`: Implements this section of logic starting with `# Timing metrics (milliseconds)`.
- `L121-L123`: Implements this section of logic starting with `# Resource metrics`.
- `L125-L128`: Implements this section of logic starting with `# Request details`.
- `L130-L131`: Implements this section of logic starting with `# Extra data`.
- `L133-L134`: Implements this section of logic starting with `# Timestamp`.
- `L136-L137`: Implements this section of logic starting with `# Relationships`.
- `L139-L143`: Implements this section of logic starting with `# Table arguments`.
- `L145-L146`: Defines the `__repr__` function and the logic it executes.
- `L149-L153`: Defines `UptimeCheck`. Uptime Monitoring - Track service availability.
- `L155`: Initializes module-level state or configuration such as `id`.
- `L157-L160`: Implements this section of logic starting with `# Check configuration`.
- `L162-L165`: Implements this section of logic starting with `# Check result`.
- `L167-L168`: Implements this section of logic starting with `# Error details`.
- `L170-L171`: Implements this section of logic starting with `# Extra data`.
- `L173-L174`: Implements this section of logic starting with `# Timestamp`.
- `L176-L180`: Implements this section of logic starting with `# Table arguments`.
- `L182-L184`: Defines the `__repr__` function and the logic it executes.
- `L186-L198`: Defines `to_dict`. Convert to dictionary.
- `L201-L205`: Defines `ErrorLog`. Error Logs - Track application errors and exceptions.
- `L207`: Initializes module-level state or configuration such as `id`.
- `L209-L212`: Implements this section of logic starting with `# Error identification`.
- `L214-L218`: Implements this section of logic starting with `# Error details`.
- `L220-L224`: Implements this section of logic starting with `# Context`.
- `L226-L228`: Implements this section of logic starting with `# Request details`.
- `L230-L231`: Implements this section of logic starting with `# Severity`.
- `L233-L236`: Implements this section of logic starting with `# Error count (for deduplication)`.
- `L238-L242`: Implements this section of logic starting with `# Resolution`.
- `L244-L245`: Implements this section of logic starting with `# Extra data`.
- `L247-L248`: Implements this section of logic starting with `# Timestamp`.
- `L250-L252`: Implements this section of logic starting with `# Relationships`.
- `L254-L259`: Implements this section of logic starting with `# Table arguments`.
- `L261-L262`: Defines the `__repr__` function and the logic it executes.
- `L264-L278`: Defines `to_dict`. Convert to dictionary.
