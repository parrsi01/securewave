# References and source traceability

External sources accessed 6 October 2026. The report's implementation claims
come from this repository; external references explain the underlying
protocols and platform semantics. Links remain useful without reproducing the
referenced papers or standards.

- [1] J. A. Donenfeld, *WireGuard: Next Generation Kernel Network Tunnel*,
  protocol paper, revision 1 June 2020. [Original paper](https://www.wireguard.com/papers/wireguard.pdf).
- [2] PostgreSQL Global Development Group, *Explicit Locking*, PostgreSQL
  documentation. [Row and transaction locks](https://www.postgresql.org/docs/current/explicit-locking.html).
- [3] M. Jones, J. Bradley and N. Sakimura, *JSON Web Token (JWT)*, RFC 7519,
  May 2015. [RFC 7519](https://www.rfc-editor.org/rfc/rfc7519).
- [4] Linux man-pages project, *pidfd_open(2)*. [Process descriptors](https://man7.org/linux/man-pages/man2/pidfd_open.2.html).
- [5] freedesktop.org, *Secret Service API*. [Specification](https://specifications.freedesktop.org/secret-service/latest/).
- [6] E. Rescorla, *The Transport Layer Security (TLS) Protocol Version 1.3*,
  RFC 8446, August 2018. [RFC 8446](https://www.rfc-editor.org/rfc/rfc8446).
- [7] GLib project, *FileSetContentsFlags* and *g_file_set_contents_full*.
  [Flags](https://docs.gtk.org/glib/flags.FileSetContentsFlags.html) and
  [write semantics](https://docs.gtk.org/glib/func.file_set_contents_full.html).
- [8] Flutter project, *Writing custom platform-specific code*.
  [Platform channels](https://docs.flutter.dev/platform-integration/platform-channels).
- [9] S. Parris et al., *Decentralized Federated Detection of Network Anomalies
  in Mobile Networks*, author's supplied IEEE-format manuscript, 2025.
  [Reference manuscript](https://github.com/parrsi01/Decentralized-Federated-Detection-of-Network-Anomalies-in-Mobile-Networks/blob/main/Research/IEEE_conference_paper_simon_parris.pdf).
- [10] PyJWT project, *Changelog*, version 2.15.0.
  [Dependency release notes](https://pyjwt.readthedocs.io/en/2.15.0/changelog.html).

## Code-to-claim map

| Claim | Primary source | Verification entrypoint |
| --- | --- | --- |
| Endpoint-specific auth behavior | app API service; routes/auth.py; jwt_service.py | Flutter API tests; backend auth contracts |
| Client-owned peer identity | app.dart; routes/vpn.py | test_vpn_client_owned_config.py |
| Verified connection | vpn_service.dart | Flutter WireGuard service tests; installed harness |
| Privileged operation boundary | my_application.cc; securewave_helperd.cc; securewave-wg-quick | Native helper and wrapper tests |
| Durable measured counters | usage_recorder.h; securewave-usage-reporter.py | Native recorder cases; crash acceptance |
| Idempotent accounting | usage_metering_service.py; usage_recording.py | test_usage_recording.py; test_usage_postgres.py |
| Additive legacy migration | migrate_usage_recording.py | Real PostgreSQL migration test |
| Version/provenance | VERSION; release_metadata.py; pubspec.yaml; build_deb.sh | Repository checks; extracted package markers |

For runnable commands and exact current results, see the
[testing guide](../development/testing.md) and
[validation record](../current-state.md). Commit history and archived records
retain earlier design and release evidence.
