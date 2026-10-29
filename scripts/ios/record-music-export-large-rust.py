"""Authenticate the actual new Rust result and affected crate checks."""
import hashlib
import json
import os
from pathlib import Path
import re

build = Path('ios/build'); plan = json.loads((build / 'preserved-plugin-integration.json').read_text('utf-8'))
assert plan['block'] == 'music-export-large' and plan['source'] == os.environ['GITHUB_SHA']
logs = {name: (build / 'logs' / name).read_bytes() for name in ['music-large-core-check.log', 'music-large-bridge-check.log', 'music-large-rust-test.log']}
clean = lambda data: re.sub(r'\x1b\[[0-9;]*m', '', data.decode('utf-8', errors='replace'))
for name in ['music-large-core-check.log', 'music-large-bridge-check.log']:
    text = clean(logs[name]); assert re.search(r'Finished .*dev.*profile', text), (name, 'Missing completed cargo check')
    assert not re.search(r'(?m)^error(?:\[|:)', text), name
rows = [dict(case=match[1], result=match[2]) for match in re.finditer(r'^test (music::\S+) \.\.\. (ok|FAILED|ignored)\s*$', clean(logs['music-large-rust-test.log']), re.M)]
assert rows == [dict(case=plan['selected_rust_cases'][0], result='ok')]
assert 'test result: ok. 1 passed; 0 failed; 0 ignored;' in clean(logs['music-large-rust-test.log'])
proof = dict(source=plan['source'], actual_rows=rows, status='pass', cargo_core_check_passed=True, cargo_bridge_check_passed=True,
    log_sha256={name: hashlib.sha256(data).hexdigest() for name, data in logs.items()},
    inputs={name: hashlib.sha256(Path(name).read_bytes()).hexdigest() for name in ['harbor-core/src/music.rs', 'harbor-core/Cargo.toml', 'harbor-ios-bridge/Cargo.toml']},
    desktop_cargo_check_claimed=False, unrelated_approved_rust_cases_repeated=False, full_desktop_parity_complete=False, ipa_created=False)
(build / plan['rust_results']).write_text(json.dumps(proof, indent=2) + '\n', 'utf-8')
print(json.dumps(proof), flush=True)
