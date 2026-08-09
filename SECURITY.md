# Security policy

Report vulnerabilities through GitHub private vulnerability reporting. Do not
include credentials, private keys, customer data, or unredacted operational
logs in an issue.

The supported product is the Linux WireGuard beta. Preserve the security floor:
passwords are hashed, bearer tokens are validated, production secrets come from
the environment or a secret store, and the privileged helper accepts only its
contract-13 operations and allowlisted users.

Local tests and source inspection do not authorize changes to the live API,
database, Hetzner host, or published downloads. Obtain operator authorization
before testing those systems.
