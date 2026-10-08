#!/usr/bin/env python3
"""Check the established palette, minimum CSS text sizes and mobile pricing."""
from pathlib import Path
import hashlib
import json
import re

root = Path(__file__).parents[1] / 'static'
css = (root / 'css/web_ui_v1.css').read_text()
colors = re.findall(r'#[0-9a-fA-F]{3,8}\b|rgba?\([^)]*\)', css)
assert hashlib.sha256('\n'.join(colors).encode()).hexdigest() == 'dd7c36d7815d5424377ccc512ad838e8fd9bca7156785f79d68414dc4b53d877', 'Existing palette changed'
assert all(float(size) >= 14 for size in re.findall(r'font-size: (\d+(?:\.\d+)?)px', css)), 'Small CSS text reintroduced'
assert 'font-size: 18px;' in css
assert re.search(r'@media \(max-width: 1200px\)\s*{\s*\.plans-grid { grid-template-columns: 1fr; }', css), 'Pricing must stack on smaller screens'
plans = (root / 'subscription.html').read_text()
assert 'style="grid-template-columns:' not in plans, 'Inline columns bypass mobile CSS'
assert '$9.99' in plans and '$99.99' in plans and 'USD' in plans
for page in root.glob('*.html'):
    source = page.read_text()
    assert 'name="viewport"' in source, page.name
    assert re.search(r'/css/web_ui_v1\.css\?v=20261006-(?:open-login|login-spacing)', source), page.name
    assert 'href="/#download"' not in source, page.name
manifest = json.loads((root / 'downloads/manifest.json').read_text())
assert manifest['version'] == '1.0.0'
assert len(manifest['downloads']) == 1
assert re.fullmatch(r'securewave-vpn_1\.0\.0_arm64(?:-(?:ui|monthly)-[0-9a-f]{12})?\.deb', manifest['downloads'][0]['filename'])
assert set(manifest['downloads'][0]) <= {'platform', 'architecture', 'filename', 'url', 'version', 'status', 'notes', 'checksum_sha256', 'source_sha', 'evidence_url', 'evidence_label'}, 'Download fields must match the live strict manifest schema'
assert manifest['downloads'][0]['source_sha'][:12] in manifest['downloads'][0]['filename']
print('PASS: existing palette; minimum CSS text sizes; responsive pricing; explicit billing; page metadata; one release.')
