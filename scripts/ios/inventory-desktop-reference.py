"""Inventory a pinned Desktop reference without claiming unverified parity."""
import argparse
import hashlib
import json
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--reference', type=Path, required=True)
args = parser.parse_args()
reference = args.reference.resolve(strict=True)
commit = '0834340cec5531650bfe78cd628628702e636987'
version = '0.9.132'
package = json.loads((reference / 'package.json').read_text('utf-8'))
assert package['version'] == version
settings_path = 'src/lib/settings/types.ts'
nav_path = 'src/chrome/nav-items.tsx'
settings_source = (reference / settings_path).read_text('utf-8')
start = settings_source.index('export type Settings = {')
end = settings_source.index('\n};', start)
settings = [(m[1], settings_source[:start + m.start()].count('\n') + 1) for m in re.finditer(r'^  (\w+)(?:\?)?:', settings_source[start:end], re.M)]
nav_source = (reference / nav_path).read_text('utf-8')
rooms = re.findall(r'"([a-z]+)"', re.search(r'export type NavItemId =([\s\S]*?);', nav_source)[1])
assert 'games' in rooms and len(set(rooms)) == len(rooms)
keys = [key for key, _ in settings]
assert len(set(keys)) == len(keys)
pattern = re.compile(r'\b(' + '|'.join(map(re.escape, keys)) + r')\b')
native_candidates = {key: [] for key in keys}
for path in sorted((root / 'ios/Harbor').rglob('*.swift')):
    for key in set(pattern.findall(path.read_text('utf-8'))):
        native_candidates[key].append(path.relative_to(root).as_posix())
historical = json.loads((root / 'docs/ios/beta-parity-status.json').read_text('utf-8'))
groups = []
for name in ['features.json', 'beta-extra-features.json']:
    groups.extend(json.loads((root / 'docs/ios' / name).read_text('utf-8')))
behaviors = []
for group in groups:
    for name in group['features']:
        behaviors.append(dict(id=name, desktop_source=group['source'], source_present=(reference / group['source']).is_file(), review='pending_reference_review', historical_evidence=historical.get(name)))
source_paths = sorted(path.relative_to(reference).as_posix() for prefix in ['src', 'src-tauri/src', 'harbor-core/src'] for path in (reference / prefix).rglob('*') if path.is_file() and path.suffix in ['.ts', '.tsx', '.rs'])
lock_paths = ['package.json', settings_path, nav_path, 'src/views/anime.tsx', 'src/views/shows.tsx', 'src/lib/stremio.ts', 'src/lib/anime-detect.ts', 'src/views/settings/groups.ts']
lock = dict(version=version, commit=commit, authority='Owner screenshot and explicit 1:1 scope, 2026-10-17', official_release='https://github.com/harborstremio-linux/harbor-linux-builds/releases/tag/beta-v0.9.132', recovered_source='https://github.com/Said129/harbor/tree/' + commit, files={name: hashlib.sha256((reference / name).read_bytes()).hexdigest() for name in lock_paths})
lock_path = root / 'docs/ios/desktop-reference-0.9.132.json'
if lock_path.exists():
    assert json.loads(lock_path.read_text('utf-8')) == lock, 'Pinned reference changed'
else:
    lock_path.write_text(json.dumps(lock, indent=2) + '\n', 'utf-8')
inventory = dict(schema=1, reference=lock_path.relative_to(root).as_posix(), version=version, commit=commit, scope='docs/ios/DESKTOP_PARITY_0_9_132.md', counted_as_completion=False, note='Declared keys, lexical native candidates and historical evidence are an audit index. They do not establish runtime equivalence or a completion percentage. Review additional behaviors in all source modules before closing the goal.', rooms=[dict(id=room, status='excluded_by_owner' if room == 'games' else 'pending_reference_review', reason='PC game libraries and execution are explicitly excluded by the owner.' if room == 'games' else None) for room in rooms], behaviors=behaviors, settings=[dict(id=key, desktop_source=settings_path, line=line, native_candidates=native_candidates[key], review='pending_reference_review', historical_evidence=historical.get('Setting: ' + key)) for key, line in settings], source_modules=source_paths)
(root / 'docs/ios/desktop-parity-0.9.132.json').write_text(json.dumps(inventory, indent=2, ensure_ascii=False) + '\n', 'utf-8')
print(json.dumps(dict(version=version, commit=commit, rooms=len(rooms), excluded_rooms=['games'], behaviors=len(behaviors), declared_settings=len(settings), source_modules=len(source_paths), percentage_not_established=True)))
