"""Authenticate the original outcome of the one changed public IPv4 classifier."""
import hashlib
import json
import os
from pathlib import Path
import re

build = Path('ios/build'); plan = json.loads((build / 'preserved-plugin-integration.json').read_text('utf-8'))
assert plan['block'] == 'music-public-network' and plan['source'] == os.environ['GITHUB_SHA']
path = build / 'logs/music-public-network-rust.log'; body = path.read_bytes()
text = re.sub(r'\x1b\[[0-9;]*m', '', body.decode('utf-8', errors='replace'))
rows = [dict(case=m[1], result=m[2]) for m in re.finditer(r'^test (plugin_http::\S+) \.\.\. (ok|FAILED|ignored)\s*$', text, re.MULTILINE)]
valid = len(rows) == 1 and rows[0]['case'] in plan['selected_rust_cases'] and rows[0]['result'] == 'ok'
proof = dict(source=plan['source'], actual_rows=rows, status='pass' if valid else 'failure',
    original_log_sha256=hashlib.sha256(body).hexdigest(), unrelated_music_rust_cases_repeated=False,
    production_check_log_sha256=hashlib.sha256((build / 'logs/music-public-network-check.log').read_bytes()).hexdigest(),
    full_desktop_parity_complete=False, ipa_created=False)
(build / 'canonical/MusicPublicNetworkRust.json').write_text(json.dumps(proof, indent=2) + '\n', 'utf-8')
print(json.dumps(proof), flush=True)
if not valid: raise SystemExit('The changed public-address classification has not passed.')
