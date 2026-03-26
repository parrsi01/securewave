# `models/usage_analytics.py`

Purpose: This module defines the database model for usage analytics records used by SecureWave.

## Line Walkthrough

- `L1-L3`: Module or block docstring that describes the responsibility of this section.
- `L5-L8`: Imports the dependencies used later in this module, including datetime, typing, sqlalchemy.
- `L10-L11`: Imports the dependencies used later in this module, including database, utils.
- `L14-L19`: Defines `UserUsageStats`. Aggregated usage statistics per user Updated periodically by analytics service.
- `L21-L22`: Initializes module-level state or configuration such as `id, user_id`.
- `L24-L29`: Implements this section of logic starting with `# Connection statistics`.
- `L31-L35`: Implements this section of logic starting with `# Data usage`.
- `L37-L40`: Implements this section of logic starting with `# Server usage`.
- `L42-L46`: Implements this section of logic starting with `# Quality metrics`.
- `L48-L52`: Implements this section of logic starting with `# Account activity`.
- `L54-L57`: Implements this section of logic starting with `# Subscription`.
- `L59-L62`: Implements this section of logic starting with `# Support`.
- `L64-L67`: Implements this section of logic starting with `# Timestamps`.
- `L69-L70`: Implements this section of logic starting with `# Relationships`.
- `L72-L73`: Defines the `__repr__` function and the logic it executes.
- `L75-L94`: Defines `to_dict`. Convert to dictionary.
- `L97-L105`: Defines `DailyUsageMetrics`. Daily aggregated metrics for analytics and billing One row per user per day.
- `L107-L109`: Initializes module-level state or configuration such as `id, user_id, date`.
- `L111-L116`: Implements this section of logic starting with `# Daily statistics`.
- `L118-L121`: Implements this section of logic starting with `# Quality`.
- `L123-L124`: Implements this section of logic starting with `# Server usage`.
- `L126`: Initializes module-level state or configuration such as `created_at`.
- `L128-L129`: Implements this section of logic starting with `# Relationships`.
- `L131-L132`: Defines the `__repr__` function and the logic it executes.
- `L134-L145`: Defines `to_dict`. Convert to dictionary.
- `L148-L153`: Defines `AbuseDetectionLog`. Abuse detection and security incident logs Tracks suspicious activity and policy violations.
- `L155-L156`: Initializes module-level state or configuration such as `id, user_id`.
- `L158-L161`: Implements this section of logic starting with `# Incident details`.
- `L163-L164`: Implements this section of logic starting with `# Evidence/extra data`.
- `L166-L168`: Implements this section of logic starting with `# Detection`.
- `L170-L173`: Implements this section of logic starting with `# Action taken`.
- `L175-L177`: Implements this section of logic starting with `# Status`.
- `L179-L181`: Implements this section of logic starting with `# Timestamps`.
- `L183-L186`: Implements this section of logic starting with `# Relationships`.
- `L188-L189`: Defines the `__repr__` function and the logic it executes.
- `L191-L205`: Defines `to_dict`. Convert to dictionary.
- `L208-L213`: Defines `SystemMetrics`. System-wide metrics and health indicators Aggregated from all servers and users.
- `L215-L216`: Initializes module-level state or configuration such as `id, timestamp`.
- `L218-L223`: Implements this section of logic starting with `# User metrics`.
- `L225-L228`: Implements this section of logic starting with `# Connection metrics`.
- `L230-L235`: Implements this section of logic starting with `# Server metrics`.
- `L237-L240`: Implements this section of logic starting with `# Bandwidth`.
- `L242-L245`: Implements this section of logic starting with `# Quality`.
- `L247-L251`: Implements this section of logic starting with `# Subscription metrics`.
- `L253-L256`: Implements this section of logic starting with `# Support metrics`.
- `L258-L260`: Implements this section of logic starting with `# Security`.
- `L262-L263`: Defines the `__repr__` function and the logic it executes.
- `L265-L279`: Defines `to_dict`. Convert to dictionary.
