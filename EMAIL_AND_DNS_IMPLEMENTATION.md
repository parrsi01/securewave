# Email and DNS Implementation

## Email

Configure SMTP via environment variables:

- `SMTP_HOST`
- `SMTP_PORT`
- `SMTP_USER`
- `SMTP_PASSWORD`

## DNS

- Point your domain A record at the server IP
- Optional CNAME for `www` to your canonical domain

See `services/domain_manager.py` for DNS verification helper logic.
