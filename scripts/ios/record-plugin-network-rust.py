"""Preserve exact outcomes of the two Rust contracts affected by the atomic API rename."""
import hashlib
import json
import os
from pathlib import Path
import re

directory = Path('ios/build')
plan = json.loads((directory / 'preserved-plugin-network.json').read_text('utf-8'))
assert plan['source'] == os.environ['GITHUB_SHA']
path = directory / 'logs/plugin-network-rust-tests.log'
data = path.read_bytes()
text = re.sub(r'\x1b\[[0-9;]*m', '', data.decode('utf-8', errors='replace'))
rows = [dict(case=match[1], result=match[2]) for match in re.finditer(r'^test (plugin_\S+) \.\.\. (ok|FAILED|ignored)\s*$', text, re.MULTILINE)]
expected = set(plan['selected_rust_cases'])
assert len(expected) == 2
valid = len(rows) == len({row['case'] for row in rows}) == 2 and {row['case'] for row in rows} == expected and all(row['result'] == 'ok' for row in rows)
result = dict(source=plan['source'], status='pass' if valid else 'partial-failure', expected_cases=sorted(expected), actual_rows=rows,
    original_log_sha256=hashlib.sha256(data).hexdigest(), unrelated_previous_rust_tests_repeated=False,
    affected_atomic_cases_reexecuted=2, retained_http_cases=6, full_desktop_parity_complete=False, ipa_created=False)
output = directory / 'canonical/PluginNetworkRust.json'; output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(result, indent=2) + '\n', 'utf-8')
print('HARBOR_PLUGIN_NETWORK_RUST ' + json.dumps(result), flush=True)
if not valid: raise SystemExit('Only original failed, missing or unexecuted networking contracts remain pending.')
