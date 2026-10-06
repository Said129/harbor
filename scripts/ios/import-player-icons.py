"""Preserve Desktop player vectors and exact-duration PNGs in native assets."""
import argparse
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--reference", required=True, type=Path)
reference = parser.parse_args().reference.resolve(strict=True)
root = Path(__file__).resolve().parents[2]
provenance_path = root / "docs/ios/beta-vector-provenance.json"
provenance = json.loads(provenance_path.read_text(encoding="utf-8"))
assets = root / "ios/Harbor/Assets.xcassets"


def image(name, data, extension, template):
    target = assets / f"player-{name}.imageset"
    target.mkdir(exist_ok=True)
    filename = "icon." + extension
    if extension == "svg":
        data = ("\n".join(line.rstrip() for line in data.decode("utf-8").splitlines()) + "\n").encode("utf-8")
    (target / filename).write_bytes(data)
    contents = {"images": [{"idiom": "universal", "filename": filename}], "info": {"version": 1, "author": "xcode"}, "properties": {"template-rendering-intent": "template" if template else "original"}}
    if extension == "svg":
        contents["properties"]["preserves-vector-representation"] = True
    (target / "Contents.json").write_bytes((json.dumps(contents, indent=2) + "\n").encode("utf-8"))


names = "back audio subtitle aspect speed play-pause--paused play-pause--playing seek-back seek-forward".split()
for name in names:
    relative = f"public/player-icons/{name}.svg"
    data = (reference / relative).read_bytes()
    parsed = ET.fromstring(data)
    if parsed.attrib.get("viewBox") != "0 0 512 512" or any(element.tag.rsplit("}", 1)[-1] not in {"svg", "g", "path"} for element in parsed.iter()):
        raise ValueError(f"Unexpected original player geometry: {name}")
    image(name, data, "svg", True)
    if name in {"seek-back", "seek-forward"}:
        # The default master contains a baked-in 10. Keep its exact arrow path
        # for native custom intervals; supported intervals use untouched PNGs.
        arrow = parsed.find("{http://www.w3.org/2000/svg}path")
        if arrow is None:
            raise ValueError("Missing original seek arrow")
        svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><path fill="#ffffff" d="' + arrow.attrib["d"] + '"/></svg>\n'
        image(name + "-custom", svg.encode("utf-8"), "svg", True)
    provenance["files"][relative] = hashlib.sha256(data).hexdigest()
for direction in ["back", "forward"]:
    for seconds in [1, 3, 5, 10, 15, 30, 60, 90]:
        name = f"seek-{direction}-{seconds}"
        relative = f"public/player-icons/{name}.png"
        data = (reference / relative).read_bytes()
        if not data.startswith(b"\x89PNG\r\n\x1a\n"):
            raise ValueError("Expected original seek PNG")
        image(name, data, "png", False)
        provenance["files"][relative] = hashlib.sha256(data).hexdigest()
provenance_path.write_bytes((json.dumps(provenance, indent=2) + "\n").encode("utf-8"))
print("Preserved 25 original player assets and two original-arrow adaptations for custom intervals")
