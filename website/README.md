# SecureWave website

This folder owns the public website assets independently of the Flutter VPN
app. The source snapshot preserves the production site's navy/black and cyan
palette, fonts, illustrations, component styling and page structure. The
October 2026 update changes readability, copy and download publication only.

## Find your way

| Path | Responsibility |
| --- | --- |
| `static/index.html` | Homepage, feature summary and plan preview |
| `static/subscription.html` | Free/Premium pricing, allowances and billing explanation |
| `static/download.html` | Supported release, compatibility and installation steps |
| `static/css/web_ui_v1.css` | Shared typography and existing responsive visual system |
| `static/js/downloads.js` | Verified catalog rendering and compatible-device recommendation |
| `static/js/site.js` | Navigation and published VPN app version display |
| `static/downloads/manifest.json` | The single public 1.0.0 package and exact checksum/source identity |
| `patches/download-catalog-version.patch` | Website download router correction on the separate production backend |
| `tests/` | Local selector and design checks; read-only live publication verification |

The production server includes an older, larger web backend not contained in
this consolidated application repository. Its download router previously used
the backend version for the catalog header. The small patch makes that header
reflect the single version actually listed, without changing authentication,
billing, peer provisioning or tunnel behavior. Do not deploy the consolidated
backend over the website deployment just to update these assets.

## Preview and verify

From the repository root:

```sh
python3 -m http.server 8080 --directory website/static
node website/tests/check_download_selector.cjs
python3 website/tests/check_design_contract.py
python3 website/tests/verify_public_downloads.py
```

The local preview falls back to the source manifest when its API is absent.
Installers are deliberately not stored in Git; the local preview cannot serve
the package unless you separately supply the verified release artifact.
Account and payment interactions require the real backend and are not mocked
by this preview. The public verification script only reads HTTPS endpoints;
it downloads package bytes and checks compatibility and retired URLs.

## Publish website updates

1. Preserve the active production release path and hashes of every file to be
   replaced. Stop if either changes unexpectedly.
2. Back up affected website assets, the website download router and retired
   installers outside every public static directory.
3. Upload the verified 1.0.0 package to private staging. Check its byte size,
   SHA-256 and source sidecar before publishing.
4. Replace only reviewed static assets and the manifest atomically. Apply the
   catalog-version patch only if its context matches. The catalog module needs
   an API service restart when this patch changes; ordinary static updates do
   not. Leave all other backend and app files alone.
5. Remove retired installers from all public directories. Preserve them in the
   private backup. Test direct/static/API routes as well as the catalog.
6. Run the checks above and compare deployed HTML/CSS/JS bytes with Git source.

See [the publication record](../docs/development/website-readability-2026-10-06.md)
for the completed update and its verification limits.
