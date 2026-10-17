"""Import original Desktop beta vectors into native template image sets."""
import hashlib
import json
from pathlib import Path
import re
import sys

source = Path(sys.argv[1]).resolve(strict=True)
repo = Path(__file__).resolve().parents[2]
assets = repo / 'ios/Harbor/Assets.xcassets'
provenance = {}
for subfolder, prefix in [('nav-icons', 'nav'), ('ui-icons', 'ui')]:
    for original in (source / 'src/assets' / subfolder).glob('*.svg'):
        target = assets / f'{prefix}-{original.stem}.imageset'
        target.mkdir(exist_ok=True)
        vector = original.read_text(encoding='utf-8')
        vector = re.sub(r'<\?xml[^>]*\?>|<!DOCTYPE[^>]*>', '', vector)
        vector = re.sub(r'(<svg[^>]*?)width="[^"]*"', r'\1width="26"', vector, count=1)
        vector = re.sub(r'(<svg[^>]*?)height="[^"]*"', r'\1height="26"', vector, count=1)
        # The image catalog supplies tint. Geometry remains unchanged.
        (target / 'icon.svg').write_text(vector + '\n', encoding='utf-8')
        (target / 'Contents.json').write_text(json.dumps({'images': [{'idiom': 'universal', 'filename': 'icon.svg'}], 'info': {'version': 1, 'author': 'xcode'}, 'properties': {'preserves-vector-representation': True, 'template-rendering-intent': 'template'}}, indent=2) + '\n')
        provenance[str(original.relative_to(source)).replace('\\', '/')] = hashlib.sha256(original.read_bytes()).hexdigest()
mark_source = source / 'src/components/icons/harbor-mark.tsx'
mark = re.search(r'(<g transform=.*?</g>)', mark_source.read_text(), re.S).group(1)
mark = re.sub(r' className="[^"]*"', '', mark)
target = assets / 'harbor-mark.imageset'
target.mkdir(exist_ok=True)
(target / 'mark.svg').write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="700" height="642.88" viewBox="0 0 700 642.88" fill="#fff">{mark}</svg>\n')
(target / 'Contents.json').write_text(json.dumps({'images': [{'idiom': 'universal', 'filename': 'mark.svg'}], 'info': {'version': 1, 'author': 'xcode'}, 'properties': {'preserves-vector-representation': True, 'template-rendering-intent': 'template'}}, indent=2) + '\n')
provenance[str(mark_source.relative_to(source)).replace('\\', '/')] = hashlib.sha256(mark_source.read_bytes()).hexdigest()
(repo / 'docs/ios/beta-vector-provenance.json').write_text(json.dumps({'repository': 'harborstremio/harbor', 'commit': '19ddc311a397eb3483b5c978d2cf2bbb3f7f479f', 'version': '0.9.128', 'requestedReference': '0.9.130', 'notes': 'Beta updater confirms 0.9.130; public beta source checkpoint is 0.9.128. Screenshots supplied by owner remain the visual reference for 0.9.130. No claim of source-identical 0.9.130 assets.', 'files': provenance}, indent=2) + '\n')
print(f'Imported {len(provenance)} original vector sources')
