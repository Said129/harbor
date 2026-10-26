"""Preserve Desktop's preview pixels as iOS-compatible bundled PNG resources."""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--reference', type=Path, required=True)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
assert json.loads((args.reference / 'package.json').read_text('utf-8'))['version'] == '0.9.132'
target = repo / 'ios/Harbor/SettingsPreview'
target.mkdir(exist_ok=True)
names = ['the-general-poster', 'the-general-still', 'sherlock-jr-poster', 'the-kid-poster', 'safety-last-poster']
records = []
for name in names:
    source = args.reference / 'src/assets/settings-preview' / (name + '.webp')
    destination = target / (name + '.png')
    pixels = Image.open(source).convert('RGB')
    pixels.save(destination, optimize=True)
    assert Image.open(destination).convert('RGB').tobytes() == pixels.tobytes()
    records.append(dict(file=destination.name, source=source.name, source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                        sha256=hashlib.sha256(destination.read_bytes()).hexdigest(), width=pixels.width, height=pixels.height))
(target / 'source.json').write_text(json.dumps(dict(reference='0834340cec5531650bfe78cd628628702e636987', unchanged_decoded_pixels=True, images=records), indent=2) + '\n', 'utf-8')
print(json.dumps(dict(images=len(records), unchanged_decoded_pixels=True, bundled_bytes=sum((target / (name + '.png')).stat().st_size for name in names))))
