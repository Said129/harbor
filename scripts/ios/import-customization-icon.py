"""Preserve the original Desktop page-customization pencil path in an image set."""
import hashlib
import json
from pathlib import Path
import re
import sys

reference = Path(sys.argv[1]).resolve(strict=True)
root = Path(__file__).resolve().parents[2]
relative = 'src/components/icons/pencil-outline.tsx'
source = reference / relative
path = re.search(r'<path d="([^"]+)" fill="currentColor"', source.read_text(encoding='utf-8'))
if path is None:
    raise ValueError('Original pencil path not found')
target = root / 'ios/Harbor/Assets.xcassets/ui-pencil-outline.imageset'
target.mkdir(exist_ok=True)
svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 512 512"><path d="{path[1]}" fill="#fff"/></svg>\n'
(target / 'icon.svg').write_bytes(svg.encode('utf-8'))
contents = {'images': [{'idiom': 'universal', 'filename': 'icon.svg'}], 'info': {'version': 1, 'author': 'xcode'}, 'properties': {'preserves-vector-representation': True, 'template-rendering-intent': 'template'}}
(target / 'Contents.json').write_bytes((json.dumps(contents, indent=2) + '\n').encode('utf-8'))
provenance_path = root / 'docs/ios/beta-vector-provenance.json'
provenance = json.loads(provenance_path.read_text(encoding='utf-8'))
provenance['files'][relative] = hashlib.sha256(source.read_bytes()).hexdigest()
provenance_path.write_bytes((json.dumps(provenance, indent=2) + '\n').encode('utf-8'))
print('Imported original page-customization pencil geometry')
