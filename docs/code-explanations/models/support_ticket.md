# `models/support_ticket.py`

Purpose: This module defines the database model for support ticket records used by SecureWave.

## Line Walkthrough

- `L1-L3`: Module or block docstring that describes the responsibility of this section.
- `L5-L9`: Imports the dependencies used later in this module, including datetime, typing, sqlalchemy, enum.
- `L11-L12`: Imports the dependencies used later in this module, including database, utils.
- `L15-L20`: Defines `TicketPriority`. Ticket priority levels.
- `L23-L30`: Defines `TicketStatus`. Ticket status.
- `L33-L41`: Defines `TicketCategory`. Ticket categories.
- `L44-L48`: Defines `SupportTicket`. Support ticket model for user helpdesk.
- `L50-L51`: Initializes module-level state or configuration such as `id, ticket_number`.
- `L53-L55`: Implements this section of logic starting with `# User and assignment`.
- `L57-L62`: Implements this section of logic starting with `# Ticket details`.
- `L64-L66`: Implements this section of logic starting with `# Extra data`.
- `L68-L73`: Implements this section of logic starting with `# Timestamps`.
- `L75-L77`: Implements this section of logic starting with `# SLA tracking`.
- `L79-L81`: Implements this section of logic starting with `# Satisfaction`.
- `L83-L86`: Implements this section of logic starting with `# Relationships`.
- `L88-L89`: Defines the `__repr__` function and the logic it executes.
- `L91-L94`: Applies decorators and defines `is_open` with the wrapped behavior declared above it.
- `L96-L101`: Applies decorators and defines `response_time_seconds` with the wrapped behavior declared above it.
- `L103-L108`: Applies decorators and defines `resolution_time_seconds` with the wrapped behavior declared above it.
- `L110-L113`: Applies decorators and defines `time_since_last_update` with the wrapped behavior declared above it.
- `L115-L140`: Defines `to_dict`. Convert ticket to dictionary.
- `L142-L143`: Runs conditional logic so the module only performs this setup when the required condition is met.
- `L145`: Returns a value from the current function.
- `L148-L152`: Defines `TicketMessage`. Ticket messages/replies.
- `L154-L156`: Initializes module-level state or configuration such as `id, ticket_id, user_id`.
- `L158-L160`: Initializes module-level state or configuration such as `message, is_internal, is_automated`.
- `L162-L163`: Implements this section of logic starting with `# Attachments (JSON array of file paths/URLs)`.
- `L165`: Initializes module-level state or configuration such as `created_at`.
- `L167-L169`: Implements this section of logic starting with `# Relationships`.
- `L171-L172`: Defines the `__repr__` function and the logic it executes.
- `L174-L185`: Defines `to_dict`. Convert message to dictionary.
