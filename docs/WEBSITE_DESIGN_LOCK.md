# SecureWave website design lock

The public SecureWave marketing website must retain the Claude-authored
"Private Routing" design. It is a black/deep-navy interface with cyan and blue
accents. Purple, violet, pink-gradient, white/purple, and generic replacement
themes are not approved.

## Non-negotiable visual identity

- Background: `#03060d`
- Secondary background: `#060c18`
- Surface: `#080f20`
- Primary accent: `#00b4ff`
- Secondary accent: `#0066cc`
- Text: `#d0e8ff`
- Display font: Space Grotesk
- Technical/navigation font: JetBrains Mono
- Homepage identity: fixed 56px navigation, dot-grid background, split hero,
  SecureWave network diagram, bordered sections, and the hexagon/shield/wave
  logo

The former purple palette (`#8b5cf6`, `#c084fc`, `#f472b6`) must not appear in
public website HTML, CSS, JavaScript, or SVG assets.

## Scope rule for release updates

An app-version, checksum, filename, status, or download-link update is a data
change, not permission to redesign the website. Routine release work should be
limited to the download manifest, backend release metadata, and the smallest
rendering/test changes needed to display that data.

Do not replace the stylesheet, homepage structure, logo, typography, palette,
navigation, or section layout unless the user explicitly requests a new website
design. Do not revive `static/home.html`; `/`, `/home`, and `/home.html` resolve
to the canonical `static/index.html` homepage.

## Enforcement

`tests/unit/test_website_design_lock.py` verifies the approved palette,
typography, homepage markers, live version display, and absence of the former
purple theme. Run it together with `scripts/verify_website.sh` for every website
or download change.
