# ARM64 package evidence

Built locally on the architecture-valid host:

- `uname -m`: `aarch64`
- Debian architecture: `arm64`
- Package: `securewave-vpn_4.0.0+1_arm64.deb`
- Package architecture: `arm64`
- Contract: `10`
- SHA-256:
  `73e1cbb0340bb7dfa0d957aa540cec5d3b7f9d27a8df4e21e833adbdd01cd340`
- App ELF: ARM AArch64
- Helper daemon ELF: ARM AArch64

Verified payload categories:

- Flutter app and launcher wrapper
- root helper daemon and narrow protocol wrapper
- helper contract
- systemd unit and tmpfiles configuration
- Debian dependencies for WireGuard, OpenVPN, NetworkManager/strongSwan,
  routing, firewall, ACLs, and systemd
- post-install, pre-remove, and post-remove scripts (shell syntax)

This local build was not installed, published, copied into public downloads, or
used as x64 evidence.
