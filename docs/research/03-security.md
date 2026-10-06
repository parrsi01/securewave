# 3. Security and identity model

## 3.1 Separate account, device, process and session identities

Let u be an account, k a client public key, p the owning GUI process and s a
usage session. These identities serve different authorization decisions.
The account authorizes provisioning and access to history. The device key
identifies a WireGuard peer. The process owns a local tunnel instance. The
usage capability authorizes reports for a particular session. Substituting
one identity for another would broaden authority unnecessarily.

Client key storage is namespaced by account identifier. Reusing a key for the
same account avoids creating a new peer on every Connect action. The backend
rejects attempts to claim another account's peer identity. Revoked or inactive
peers are not eligible for new active sessions. Operational account deletion,
multi-device revocation and long-term rotation still require explicit product
policies.

## 3.2 Authentication

Registration normalizes email addresses and validates the password contract.
Passwords are stored as hashes through `hashing_service.py`. Login returns
signed access and refresh tokens and sets cookies. The native application uses
the access bearer. JWT claims include account subject, token type, expiry and
the account's token generation. The decoder explicitly allows HS256 and
checks the active account and current generation [3]. Logout increments that
generation, invalidating prior access tokens for the account.

This is a signed token, not encrypted user metadata. Token confidentiality
depends on protected storage and transport. Separate access and refresh signing
secrets are required in production. Development can generate ephemeral
secrets, which intentionally makes old sessions unusable after restart.

A login 401 means that the submitted credentials failed. A protected request's
401 can mean an expired or invalid session and routes the application back to
sign-in. Registration is unauthenticated. These endpoint-specific semantics
preserve useful error handling without suppressing genuine bad-password
rejection. The current server registration flow does not verify mailbox
ownership; its `email_verified` field must not be interpreted as independent
email delivery evidence. Native automatic refresh is not asserted here.

## 3.3 Privilege separation

The GUI runs as the desktop user. The helper owns privileged WireGuard actions.
Its request protocol has a fixed version and operation vocabulary. The helper
checks socket peer credentials and authorized group membership rather than
trusting a caller-supplied user identifier. Configuration validation rejects
unsafe ownership, modes and filesystem paths. Approved executable invocations
are constrained; the protocol does not expose an arbitrary shell endpoint.

The helper tracks the GUI process through a process descriptor where available.
A pidfd refers to the process identity and avoids treating a reused numerical
PID as the original owner [4]. A second GUI cannot silently adopt another
window's active recorded tunnel. Owner exit initiates measured finalization
and teardown. These protections depend on the daemon being installed and
running with the expected service and file permissions.

## 3.4 Configuration and transport

Local client key material uses Flutter secure storage backed by the Linux
desktop's Secret Service integration [5]. The tunnel configuration exists only
where the helper expects it, with restricted permissions, and is removed on
safe teardown. Secrets are excluded from public evidence. Runtime checks use
public peer keys, timestamps and counter values rather than printing a full
WireGuard configuration.

HTTPS protects the control-plane exchanges when certificate validation and
the deployment are configured correctly. TLS 1.3 is a relevant protocol
reference [6], but this repository analysis does not claim that every deployed
endpoint currently negotiates that version. WireGuard's authenticated
encrypted transport and cryptokey routing are supplied by the protocol [1].
No custom cipher is added by SecureWave.

## 3.5 Threats and residual risks

| Threat | Implemented response | Residual limitation |
| --- | --- | --- |
| Account token replay after logout | Token generation check | A stolen currently valid token remains dangerous until invalidated |
| Cross-account peer claim | Ownership validation | Backend/root compromise bypasses application checks |
| Arbitrary privileged command | Fixed helper protocol and validation | Approved utilities and parser remain security-critical |
| GUI failure during tunnel | Process ownership, finalization and teardown | Abrupt system loss may precede final observation |
| Duplicate reporting | Capability check, digest and sequence transaction | Hostile trusted client can fabricate its own measured data |
| Secret disclosure in evidence | Redaction and protected local artifacts | Manual screenshots or external logs need careful handling |

A complete audit would examine parser fuzzing, command timeout behavior,
permission changes, dependency supply chain and network leak scenarios. The
presence of controls is evidence of design intent and implementation, not a
certificate that all attack paths have been eliminated.
