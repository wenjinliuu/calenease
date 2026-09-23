#!/usr/bin/env python3
"""Check TLS, exact response headers, and content of all published objects."""

import hashlib
import json
import sys
import time
import urllib.request
from pathlib import Path


base, directory = sys.argv[1].rstrip('/'), Path(sys.argv[2])
index = json.loads((directory / 'index.json').read_text())
for filename in ['index.json', *(entry['url'] for entry in index['years'].values())]:
    expected = (directory / filename).read_bytes()
    for attempt in range(8):
        try:
            request = urllib.request.Request(f'{base}/{filename}', headers={'Origin': 'https://example.org'})
            with urllib.request.urlopen(request, timeout=20) as response:
                actual = response.read()
                headers = response.headers
            assert actual == expected, f'{filename}: bytes differ from candidate'
            assert headers.get('Content-Type', '').lower() == 'application/json; charset=utf-8', filename
            assert headers.get('Cache-Control') == ('max-age=3600' if filename == 'index.json' else 'max-age=86400'), filename
            assert headers.get('Access-Control-Allow-Origin') == '*', filename
            if filename != 'index.json':
                assert hashlib.sha256(actual).hexdigest() == index['years'][filename[:-5]]['sha256'], filename
            break
        except Exception:
            if attempt == 7:
                raise
            time.sleep(5)
print(f'Public HTTPS contract verified for {len(index["years"])} years and index')
