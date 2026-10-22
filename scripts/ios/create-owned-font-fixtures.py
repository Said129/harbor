"""Create reproducible, original geometric test fonts; no external font is copied."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

p = argparse.ArgumentParser(); p.add_argument('--dependencies', type=Path, required=True); args = p.parse_args()
sys.path.insert(0, str(args.dependencies))
import fontTools
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont
from fontTools.ttLib.woff2 import WOFF2FlavorData

root = Path(__file__).resolve().parents[2] / 'ios/HarborTests/Fixtures'
records = []
for flavor in ['woff', 'woff2']:
    glyph_names = ['.notdef', 'space'] + [f'g{code}' for code in sorted(set(map(ord, 'HarborABñé')))]
    builder = FontBuilder(1000, isTTF=True)
    builder.setupGlyphOrder(glyph_names)
    builder.setupCharacterMap({32: 'space', **{int(name[1:]): name for name in glyph_names[2:]}})
    glyphs = {}
    for index, name in enumerate(glyph_names):
        pen = TTGlyphPen(None)
        if name != 'space':
            pen.moveTo((50, 0)); pen.lineTo((220 + index, 700)); pen.lineTo((500, 0)); pen.closePath()
        glyphs[name] = pen.glyph()
    builder.setupGlyf(glyphs)
    builder.setupHorizontalMetrics({name: (600 + index * 7, 0 if name == 'space' else 50) for index, name in enumerate(glyph_names)})
    builder.setupHorizontalHeader(ascent=800, descent=-200)
    builder.setupNameTable(dict(familyName='Harbor Owned ' + flavor.upper(), styleName='Regular', uniqueFontIdentifier='HarborOwned-' + flavor,
        fullName='Harbor Owned ' + flavor.upper(), psName='HarborOwned-' + flavor, version='Version 1.0'))
    builder.setupOS2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=800, usWinDescent=200)
    builder.setupPost(); builder.setupMaxp()
    builder.font['head'].created = 3864672000; builder.font['head'].modified = 3864672000
    builder.font.recalcTimestamp = False
    stem = 'owned-reader-' + flavor
    original = root / (stem + '.ttf'); builder.save(original)
    font = TTFont(original, recalcTimestamp=False); font.flavor = flavor
    if flavor == 'woff2': font.flavorData = WOFF2FlavorData(transformedTables={'glyf', 'loca', 'hmtx'})
    destination = root / (stem + '.' + flavor); font.save(destination)
    restored = TTFont(destination, recalcTimestamp=False)
    assert restored.getBestCmap() == builder.font.getBestCmap()
    assert restored['hmtx'].metrics == builder.font['hmtx'].metrics
    records.append(dict(format=flavor, filename=destination.name, original=original.name,
        original_sha256=hashlib.sha256(original.read_bytes()).hexdigest(), sha256=hashlib.sha256(destination.read_bytes()).hexdigest(), bytes=destination.stat().st_size,
        postscript_name=restored['name'].getDebugName(6), text='Harbor ABñé'))
manifest = dict(schema=1, ownership='Original geometric glyph fixtures created for Harbor native tests.', fonttools=fontTools.__version__, records=records)
(root / 'owned-reader-fonts.json').write_text(json.dumps(manifest, indent=2) + '\n', 'utf-8')
print(json.dumps(manifest))
