"""Import original MusicGlyph masters with the same theme-ink normalization."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--reference", required=True, type=Path)
args = parser.parse_args()
reference = args.reference.resolve(strict=True)
root = Path(__file__).resolve().parents[2]
names = "play pause previous next shuffle repeat repeat-one volume-high volume-low volume-mute waveform music queue album artist plus close".split()
provenance_path = root / "docs/ios/beta-vector-provenance.json"
provenance = json.loads(provenance_path.read_text(encoding="utf-8"))
wrapper = "src/components/icons/music-glyph.tsx"
provenance["files"][wrapper] = hashlib.sha256((reference / wrapper).read_bytes()).hexdigest()
for name in names:
    relative = f"src/assets/music-icons/{name}.svg"
    source = reference / relative
    raw = source.read_text(encoding="utf-8")
    source_xml = ET.fromstring(raw)
    if source_xml.attrib.get("viewBox") != "0 0 24 24":
        raise ValueError(f"Unexpected original MusicGlyph bounds: {name}")
    inner = re.search(r"<svg\b[^>]*>([\s\S]*)</svg>\s*$", raw)
    if inner is None:
        raise ValueError(f"Missing SVG root: {name}")
    geometry = re.sub(r'\sid="[^"]*"', "", inner[1])
    geometry = re.sub(r'(fill|stroke)="#[0-9a-fA-F]{3,8}"', r'\1="#ffffff"', geometry)
    geometry = "\n".join(line.rstrip() for line in geometry.splitlines())
    svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">' + geometry + "</svg>\n"
    parsed = ET.fromstring(svg)
    if any(element.tag.rsplit("}", 1)[-1] not in {"svg", "g", "path", "polygon", "polyline", "circle", "ellipse", "rect", "line"} for element in parsed.iter()):
        raise ValueError(f"Unsupported original SVG geometry: {name}")
    target = root / f"ios/Harbor/Assets.xcassets/music-{name}.imageset"
    target.mkdir(exist_ok=True)
    (target / "icon.svg").write_bytes(svg.encode("utf-8"))
    contents = {"images": [{"idiom": "universal", "filename": "icon.svg"}], "info": {"version": 1, "author": "xcode"}, "properties": {"preserves-vector-representation": True, "template-rendering-intent": "template"}}
    (target / "Contents.json").write_bytes((json.dumps(contents, indent=2) + "\n").encode("utf-8"))
    provenance["files"][relative] = hashlib.sha256(source.read_bytes()).hexdigest()
provenance_path.write_bytes((json.dumps(provenance, indent=2) + "\n").encode("utf-8"))
print(f"Imported {len(names)} original MusicGlyph masters")
