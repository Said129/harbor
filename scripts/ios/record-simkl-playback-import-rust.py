"""Authenticate the failed bridge retest and preserve the actual passed core."""
import hashlib
import json
import os
from pathlib import Path
import re

root = Path('ios/build/logs')
tests = {
    'simkl-playback-import-bridge-test.log': 'tracker_percentage_crosses_the_real_abi_and_preserves_legacy_entries',
}
for name, method in tests.items():
    text = re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', (root / name).read_text('utf-8'))
    assert re.search(r'test ' + re.escape(method) + r' \.\.\. ok', text)
    assert 'test result: ok. 1 passed; 0 failed; 0 ignored;' in text
retained = json.loads(Path('ios/build/preserved-simkl-playback-core.json').read_text('utf-8'))
assert retained['source'] == os.environ['GITHUB_SHA'] and retained['original_run_authenticated'] and retained['unchanged_inputs_verified']
assert retained['production_cargo_check_passed'] and retained['retained_actual_core_cases'] == 1
logs = ['retained-simkl-playback-core.log', *tests]
proof = dict(source=os.environ['GITHUB_SHA'], cargo_check_passed=True, actual_new_rust_tests_passed=1, retained_actual_core_cases=1,
    retained_core_run=retained['inherited']['run'], retained_core_source=retained['inherited']['source'],
    unrelated_rust_tests_executed=False, logs={name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in logs})
Path('ios/build/preserved-simkl-playback-import-rust.json').write_text(json.dumps(proof, indent=2) + '\n', 'utf-8')
print(json.dumps(proof))
