"""Prepare ordinary guest data on an otherwise fresh CI simulator, never a product launch mode."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--container', required=True, type=Path)
a = p.parse_args()
container = a.container.resolve(strict=True)
assert 'CoreSimulator' in container.parts and 'Devices' in container.parts
assert container.parent.name == 'Application' and container.parent.parent.name == 'Data'
metadata = container / '.com.apple.mobile_container_manager.metadata.plist'
if metadata.is_file():
    assert plistlib.loads(metadata.read_bytes())['MCMMetadataIdentifier'] == 'site.harbor.iphone'
text = Path('ios/HarborTests/StableMobileTests.swift').read_text('utf-8')
values = re.findall(r'Data\(#"(\{"_id":"harbor-stable-removal-fixture".*?\})"#\.utf8\)', text)
assert values and len(set(values)) == 1
record = json.loads(values[0])
assert record['_id'] == 'harbor-stable-removal-fixture'
directory = container / 'Library/Application Support/Harbor'
directory.mkdir(parents=True, exist_ok=True)
filename = 'library-' + hashlib.sha256(b'guest').hexdigest() + '.json'
(directory / filename).write_text(json.dumps([record]), 'utf-8')
preferences = container / 'Library/Preferences/site.harbor.iphone.plist'
preferences.parent.mkdir(parents=True, exist_ok=True)
stored = plistlib.loads(preferences.read_bytes()) if preferences.exists() else {}
stored.update(homeMode='classic', uiLanguage='es')
preferences.write_bytes(plistlib.dumps(stored))
print('Prepared the same ordinary guest library fixture used by the approved native tests.')
