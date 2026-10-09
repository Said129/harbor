"""Import the original public Spooktober selections and artwork, without its JS runtime."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser()
parser.add_argument("--reference", type=Path, required=True)
args = parser.parse_args()
reference = args.reference.resolve(strict=True)
root = Path(__file__).resolve().parents[2]
resources = root / "ios/Harbor"
provenance_path = root / "docs/ios/beta-vector-provenance.json"
provenance = json.loads(provenance_path.read_text(encoding="utf-8"))


def original(relative):
    path = reference / relative
    data = path.read_bytes()
    provenance["files"][relative] = hashlib.sha256(data).hexdigest()
    return data


def image(name, data, extension, template=False):
    destination = resources / "Assets.xcassets" / (name + ".imageset")
    destination.mkdir(exist_ok=True)
    filename = "original." + extension
    if extension == "svg":
        data = ("\n".join(line.rstrip() for line in data.decode("utf-8").splitlines()) + "\n").encode("utf-8")
    (destination / filename).write_bytes(data)
    properties = {"preserves-vector-representation": True} if extension == "svg" else {}
    if template:
        properties["template-rendering-intent"] = "template"
    contents = {"images": [{"idiom": "universal", "filename": filename}],
                "info": {"version": 1, "author": "xcode"}, "properties": properties}
    (destination / "Contents.json").write_bytes((json.dumps(contents, indent=2) + "\n").encode())


content = original("public/spooktober/content.json")
items = json.loads(content)
if len(items) != 71 or len({item["id"] for item in items}) != 71:
    raise ValueError("Unexpected original Spooktober selection")
(resources / "SpooktoberContent.json").write_bytes((json.dumps(items, indent=2, ensure_ascii=False) + "\n").encode("utf-8"))
image("spook-pumpkin", original("public/spooktober/assets/art/pumpkin-grin.svg"), "svg")
for name in ["midnight-film", "candle", "ghost-tv", "haunted-book", "ink-eye", "candy", "moon"]:
    svg = original("public/spooktober/assets/icons/" + name + ".svg")
    ET.fromstring(svg)
    image("spook-" + name, svg, "svg")
for poster in sorted({item["poster"] for item in items if item["poster"].startswith("assets/posters/")}):
    if not re.fullmatch(r"assets/posters/[a-z-]+\.jpg", poster):
        raise ValueError("Unexpected poster path")
    image("spook-poster-" + Path(poster).stem, original("public/spooktober/" + poster), "jpg")

entry = original("src/views/spooktober/spooktober-entry.tsx").decode()
hills = re.findall(r'<path d="([^"]+)" fill="var\(--spook-(hill|field)\)"', entry)
if len(hills) != 2:
    raise ValueError("Original invitation hills missing")
for path, name in hills:
    svg = '<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="126" viewBox="0 0 1200 126"><path d="' + path + '" fill="#fff"/></svg>\n'
    image("spook-" + name, svg.encode(), "svg", template=True)
original("src/lib/spooktober-season.ts")
original("public/spooktober/native-runtime.js")
provenance_path.write_bytes((json.dumps(provenance, indent=2) + "\n").encode())
print("Imported 71 original selections, pumpkin, seven icons, two hill paths and three posters")
