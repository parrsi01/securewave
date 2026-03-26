# `models/email_log.py`

Purpose: This module defines the database model for email log records used by SecureWave.

## Line Walkthrough

- `L1-L3`: Module or block docstring that describes the responsibility of this section.
- `L5-L8`: Imports the dependencies used later in this module, including datetime, typing, sqlalchemy.
- `L10-L11`: Imports the dependencies used later in this module, including database, utils.
- `L14-L19`: Defines `EmailLog`. Email tracking and logging Tracks all emails sent through the system.
- `L21-L22`: Initializes module-level state or configuration such as `id, user_id`.
- `L24-L28`: Implements this section of logic starting with `# Email details`.
- `L30-L32`: Implements this section of logic starting with `# Email type categorization`.
- `L34-L36`: Implements this section of logic starting with `# Provider info`.
- `L38-L40`: Implements this section of logic starting with `# Status tracking`.
- `L42-L43`: Implements this section of logic starting with `# Extra data`.
- `L45-L51`: Implements this section of logic starting with `# Engagement tracking`.
- `L53-L55`: Implements this section of logic starting with `# Timestamps`.
- `L57-L58`: Implements this section of logic starting with `# Relationships`.
- `L60-L61`: Defines the `__repr__` function and the logic it executes.
- `L63-L80`: Defines `to_dict`. Convert to dictionary.
- `L83-L88`: Defines `EmailTemplate`. Email template storage Store email templates in database for easy updates.
- `L90-L94`: Initializes module-level state or configuration such as `id, name, subject, html_template, text_template`.
- `L96-L99`: Implements this section of logic starting with `# Template metadata`.
- `L101-L102`: Implements this section of logic starting with `# Status`.
- `L104-L106`: Implements this section of logic starting with `# Timestamps`.
- `L108-L109`: Defines the `__repr__` function and the logic it executes.
- `L111-L121`: Defines `to_dict`. Convert to dictionary.
