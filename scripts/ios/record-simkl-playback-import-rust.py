"""Authenticate the two actual new resume tests; no unrelated Rust replay."""
import hashlib
import json
import os
from pathlib import Path
import re

root = Path('ios/build/logs')
tests = {
    'simkl-playback-import-core-test.log': 'tracker_percentage_survives_validation_and_uses_real_runtime_from_the_same_entry',
    'simkl-playback-import-bridge-test.log': 'tracker_percentage_crosses_the_real_abi_and_preserves_legacy_entries',
}
for name, method in tests.items():
    text = (root / name).read_text('utf-8')
    assert re.search(r'test ' + re.escape(method) + r' \.\.\. ok', text)
    assert 'test result: ok. 1 passed; 0 failed; 0 ignored;' in text
check = (root / 'simkl-playback-import-rust-check.log').read_text('utf-8')
assert re.search(r'Finished `dev` profile', check)
logs = ['simkl-playback-import-rust-check.log', *tests]
proof = dict(source=os.environ['GITHUB_SHA'], cargo_check_passed=True, actual_new_rust_tests_passed=2,
    unrelated_rust_tests_executed=False, logs={name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in logs})
Path('ios/build/preserved-simkl-playback-import-rust.json').write_text(json.dumps(proof, indent=2) + '\n', 'utf-8')
print(json.dumps(proof))
