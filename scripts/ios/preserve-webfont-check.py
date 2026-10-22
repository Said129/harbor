"""Keep the actual approved font check only while every production input is identical."""
import hashlib
import json
import os
from pathlib import Path

baseline = json.loads(r'''{
  "run": 39850934986,
  "source": "702dc8f02643a72b425fa627842b8a9e3845a1d4",
  "result": "passed",
  "original_log_sha256": "51161c2d096e50544b8e1d480cd5d6393ececadc561b750acbbb2421d4865c4b",
  "evidence_archive_sha256": "d7b0bb0ae23a686420c64f9f45db7957cdf247d061d3becedef53e7000cdc2e8",
  "production_inputs": {
    "harbor-ios-bridge/src/font_decode.rs": "6417240cb9ebf7c718276613f0edd1543872a361d958f842a14875c3868ceee1",
    "harbor-ios-bridge/Cargo.toml": "628962dea76ac3e95c7f73c323f7203db3a96c6f5664acd64d12e79f925ee57f",
    "harbor-ios-bridge/Cargo.lock": "e30836b00c53796ce98bea3d0091ddc9315b9756d9a55baaa529432d3c470917",
    "harbor-ios-bridge/include/harbor_ios.h": "ac9c539894a4a46e4092de881e2629c2f451b232d3d9bae1fac53d9d17b54e0f",
    "harbor-ios-bridge/src/lib.rs": "f3ce4b397d332d8dbc14972657ce6c8c1b67c2610c8de77ab1bdf04cf684250f"
  }
}''')
for path, expected in baseline['production_inputs'].items():
    text = Path(path).read_text('utf-8')
    if path.endswith('font_decode.rs'):
        assert text.count('#[cfg(test)]') == 1
        text = text.split('#[cfg(test)]', 1)[0]
    assert hashlib.sha256(text.encode()).hexdigest() == expected, 'Production font input changed: ' + path
output = Path('ios/build/canonical/WebFontPreservedCheck.json')
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(dict(source=os.environ.get('GITHUB_SHA', 'working-tree'), inherited_check=baseline, original_approved_check_repeated=False), indent=2) + '\n', 'utf-8')
print('Retained actual cargo check from run39850934986; compile affected tests with clippy --all-targets.')
