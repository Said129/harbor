"""Use ordinary completed-guide preferences in the isolated model-test host."""
import argparse
import json
from pathlib import Path
import plistlib
import re

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--container', required=True, type=Path)
a = p.parse_args()
container = a.container.resolve(strict=True)
assert container.is_dir() and re.fullmatch('[A-Fa-f0-9-]{36}', container.name)
assert 'CoreSimulator' in container.parts and 'Application' in container.parts
folder = container / 'Library/Preferences'
folder.mkdir(parents=True, exist_ok=True)
target = folder / 'site.harbor.iphone.plist'
assert target.resolve().is_relative_to(container) and not target.is_symlink()
values = plistlib.loads(target.read_bytes()) if target.exists() else {}
assert isinstance(values, dict)
values['nativeGuide.initialized.v1'] = True
values['nativeGuide.completed.v1'] = True
temporary = folder / 'harbor-model-startup.tmp'
temporary.write_bytes(plistlib.dumps(values, fmt=plistlib.FMT_BINARY))
temporary.replace(target)
print(json.dumps(dict(ordinary_preferences=['nativeGuide.initialized.v1', 'nativeGuide.completed.v1'], guide_replay_ui_test='required separately', production_test_mode_added=False)))
