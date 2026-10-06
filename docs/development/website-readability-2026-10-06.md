# Website readability and 1.0.0 publication — 6 October 2026

The user authorized website-only readability and copy improvements and making
1.0.0 the only VPN app downloadable from the website. This update preserves
the app and its existing authentication, helper, provisioning and tunnel
contracts.

## Changes

- Body and ordinary paragraphs are now 18 px; navigation/actions are at least
  16 px; small CSS labels are at least 14 px instead of 9–11 px. The original
  font families, colours, gradients, borders and illustrations remain.
- Mobile navigation appears before larger text crowds the header. Pricing
  cards stack on smaller screens; small-screen call-to-action links wrap.
  Long checksums, commands and account information can wrap.
- Homepage and plans use the live billing catalog's Free and Premium tiers.
  Premium is USD 9.99 monthly or USD 99.99 yearly, approximately USD 8.33 per
  month when paid yearly. The previous conflicting USD 8 / USD 9 claims and
  unsupported “Most used” badge were removed. No billing prices or checkout
  backend behavior changed.
- Download guidance explicitly supports Ubuntu 24.04 ARM64 only, gives install
  steps, and stops advertising unpublished Apple handoff/demo downloads.
  Broken homepage download anchors now open the download page.
- Footer version text identifies the published VPN app rather than confusing
  it with the separate backend's historical version. The website catalog
  header likewise follows its listed release version.

## Published package

| Property | Verified value |
| --- | --- |
| Filename | `securewave-vpn_1.0.0_arm64.deb` |
| Version / architecture | `1.0.0` / `arm64` |
| Bytes | `15180502` |
| Source commit | `a9181ea8828d6b66557260042bbbcde0675c0e84` |
| SHA-256 | `9b561d5444ee39259b9dad3e656f840e4657f89db18fdbfaf2396e9a8c2bc622` |

Website assets and package publication began at **22:50 UTC**. Deployment was
limited to static assets, the download manifest, the verified package, and a
small website download-catalog version correction. The API service was
restarted to load that correction and subsequently passed public readiness.
The complete API/application source was not redeployed.

The prior website assets, router and retired package were backed up privately
under `/var/backups/securewave-website-20261006T225050Z/`. Retired artifacts
are absent from public directories; their private copies remain preserved.

## Evidence and limits

- Four public catalogs list exactly one available package, version 1.0.0.
- Real HTTPS bytes match the package size and SHA-256 through `/downloads/`,
  `/static/downloads/` and `/api/downloads/file/`.
- Twelve historical/unpublished filenames return 404 through each of those
  three route families: **36 retired URL checks**.
- ARM64 Linux receives the supported recommendation; Linux x64, Windows,
  macOS, iOS and Android receive none. Local selector tests also reject an
  unknown device.
- Deployed HTML, CSS and changed JavaScript were compared to saved source.
  Palette values and existing page IDs/control bindings were preserved.
- Browser surfaces were unavailable in this session. Responsive CSS and
  functional/publication checks passed; visual browser and mobile-device
  inspection are not claimed.

This website publication does not close the separate exact-1.0.0 post-reboot
VPN acceptance gate documented in [current state](../current-state.md).
Historical GitHub release archives remain historical evidence; this update
only controls the current website's download offering.
