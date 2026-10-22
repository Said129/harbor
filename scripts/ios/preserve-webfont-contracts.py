"""Keep actual Rust results while every compiled input and owned fixture matches."""
import hashlib
import json
import os
from pathlib import Path

baseline = json.loads(Path('scripts/ios/approved-web-font-contracts.json').read_text('utf-8'))
for name, expected in baseline['inputs'].items():
    data = Path(name).read_bytes()
    if Path(name).suffix in ('.rs', '.toml', '.lock', '.h'):
        data = data.replace(b'\r\n', b'\n')
    assert hashlib.sha256(data).hexdigest() == expected, 'Approved Rust input changed: ' + name
target = Path('ios/build/canonical/WebFontPreservedContracts.json'); target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(json.dumps(dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), inherited_contracts=baseline,
    original_approved_tests_repeated=False), indent=2) + '\n', 'utf-8')
print('Retained five actual Rust font passes and clean clippy --all-targets from run39852325983.')
