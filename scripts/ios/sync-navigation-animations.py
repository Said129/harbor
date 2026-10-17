"""Copy original Desktop navigation vectors without altering their keyframes."""
import argparse
import hashlib
import json
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--reference', type=Path, required=True)
a = p.parse_args()
root = Path(__file__).resolve().parents[2]
assert json.loads((a.reference / 'package.json').read_text('utf-8'))['version'] == '0.9.132'
names = ['home', 'catalogs', 'movies', 'shows', 'music', 'anime', 'manga', 'ebook', 'live-tv', 'playlists', 'calendar', 'library', 'collections', 'downloads', 'addons', 'settings']
folder = root / 'ios/Harbor/DesktopAnimations'
(folder / 'nav').mkdir(parents=True, exist_ok=True)
items = []
for name in names:
    relative = f'src/assets/lottie/nav/{name}.json'
    data = (a.reference / relative).read_bytes()
    value = json.loads(data)
    assert value['op'] > value['ip'] and 0 < value['fr'] <= 120
    assert value['w'] <= 2048 and value['h'] <= 2048
    assert not any(item.get('u') or item.get('p') for item in value.get('assets', [])), 'Use bundled vector-only navigation assets'
    (folder / 'nav' / (name + '.json')).write_bytes(data)
    items.append(dict(name=name, source=relative, bytes=len(data), sha256=hashlib.sha256(data).hexdigest(), start=value['ip'], end=value['op'], fps=value['fr']))
(folder / 'LICENSE-Harbor.txt').write_bytes((a.reference / 'LICENSE').read_bytes())
manifest = dict(reference='0834340cec5531650bfe78cd628628702e636987', version='0.9.132',
                renderer=dict(package='https://github.com/airbnb/lottie-spm.git', version='4.6.1', revision='0aff16288f8dc1e3dab35cbf5cf45979673fd3df', artifact_sha256='03d3f3b085da9479bcab7b0ad4b6d75a88425d27bf3c7582698fddce14c9181f'),
                behavior='Original vector keyframes. Play only during touch press or pointer hover in the foreground; respect the sidebar animation setting and Reduce Motion. Shows loops only while interacted, matching Desktop. Idle rows remain static.',
                excluded_games=True, count=len(items), bytes=sum(item['bytes'] for item in items), animations=items)
(root / 'docs/ios/desktop-navigation-animations-0.9.132.json').write_text(json.dumps(manifest, indent=2) + '\n', 'utf-8')
(root / 'ios/HarborTests/Fixtures/navigation-animation-hashes.json').write_text(json.dumps({item['name']: item['sha256'] for item in items}, indent=2) + '\n', 'utf-8')
print(f'Copied {len(items)} unchanged Desktop navigation vectors ({manifest["bytes"]} bytes); no Games assets.')
