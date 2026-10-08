#!/usr/bin/env python3
"""Read-only checks of catalogs, exact package bytes and retired public routes."""
import concurrent.futures
import hashlib
import json
from urllib.error import HTTPError
from urllib.parse import quote
from urllib.request import Request, urlopen
from pathlib import Path

BASE = 'https://securewaveapp.com'
MANIFEST = json.loads((Path(__file__).parents[1] / 'static/downloads/manifest.json').read_text())
ENTRY = MANIFEST['downloads'][0]

def get(path, user_agent='SecureWave-website-verification/1.0'):
    with urlopen(Request(BASE + path, headers={'User-Agent': user_agent, 'Cache-Control': 'no-cache'}), timeout=30) as response:
        return response.read()

def verify():
    for path in ['/api/downloads', '/api/downloads/list', '/downloads/manifest.json', '/static/downloads/manifest.json']:
        payload = json.loads(get(path))
        assert payload['version'] == '1.0.0', path
        assert len(payload['downloads']) == 1, path
        row = payload['downloads'][0]
        for key in ['filename', 'version', 'checksum_sha256', 'source_sha', 'url']:
            assert row[key] == ENTRY[key], (path, key)
        assert row['status'] == 'available', path
    for prefix in ['/downloads/', '/static/downloads/', '/api/downloads/file/']:
        data = get(prefix + ENTRY['filename'])
        assert data, prefix
        assert hashlib.sha256(data).hexdigest() == ENTRY['checksum_sha256']
    retired = [
        'securewave-vpn_1.0.0_arm64-ui-a8096ae5f8fa.deb',
        'securewave-vpn_1.0.0_arm64.deb', 'securewave-vpn_4.0.0+10_arm64.deb', 'securewave-vpn_4.0.0+11_arm64.deb',
        'securewave-vpn_4.0.0+12_arm64.deb', 'securewave-linux-arm64.deb',
        'securewave-linux-x64.deb', 'securewave-linux-x64.AppImage', 'securewave-linux-x64.tar.gz',
        'securewave-apple-release-handoff.zip', 'securewave-macos-arm64-ui-demo.zip',
        'securewave-macos-x64-ui-demo.zip', 'securewave-windows-x64-setup.exe', 'securewave-android.apk',
    ]
    paths = [prefix + quote(name) for prefix in ['/downloads/', '/static/downloads/', '/api/downloads/file/'] for name in retired]
    def is_retired(path):
        try: get(path)
        except HTTPError as error:
            assert error.code == 404, (path, error.code)
            return
        raise AssertionError('Retired download still public: ' + path)
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as executor:
        list(executor.map(is_retired, paths))
    for ua, available in [('Mozilla Linux aarch64', True), ('Mozilla Linux x86_64', False),
                          ('Mozilla iPhone', False), ('Mozilla Windows NT 10.0', False),
                          ('Mozilla Macintosh', False), ('Mozilla Android aarch64', False)]:
        detected = json.loads(get('/api/downloads/detect', ua))
        assert bool(detected['recommended_download']) == available, (ua, detected)
    assert json.loads(get('/api/ready'))['status'] in ['ready', 'ok', 'healthy']
    print(f'PASS: four catalogs; three exact package routes; {len(paths)} retired URLs; six device recommendations; API readiness.')

if __name__ == '__main__':
    verify()
