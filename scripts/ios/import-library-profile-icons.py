"""Import the Lucide geometry used by the original Desktop library/profile."""
import base64
import hashlib
import io
import json
from pathlib import Path
import re
import tarfile
from urllib.request import urlopen
import xml.etree.ElementTree as ET


def main():
    root = Path(__file__).resolve().parents[2]
    version = "0.460.0"  # The Desktop beta reference declares ^0.460.0.
    with urlopen(f"https://registry.npmjs.org/lucide-react/{version}", timeout=30) as response:
        package = json.load(response)
    with urlopen(package["dist"]["tarball"], timeout=30) as response:
        archive = response.read(20 * 1024**2 + 1)
    assert len(archive) <= 20 * 1024**2
    algorithm, integrity = package["dist"]["integrity"].split("-", 1)
    assert algorithm == "sha512"
    assert base64.b64encode(hashlib.sha512(archive).digest()).decode() == integrity
    records = {}
    with tarfile.open(fileobj=io.BytesIO(archive), mode="r:gz") as sources:
        for name in ["bookmark", "clock", "hard-drive", "image", "palette", "chevron-right"]:
            relative = f"package/dist/esm/icons/{name}.js"
            original = sources.extractfile(relative).read()
            source = original.decode("utf-8")
            match = re.search(r'createLucideIcon\("[^"]+",\s*(\[.*\])\);', source, re.S)
            assert match is not None, f"Missing declarative geometry: {name}"
            literal = re.sub(r'([,{]\s*)([A-Za-z][A-Za-z0-9_-]*)(\s*:)', r'\1"\2"\3', match[1])
            nodes = json.loads(literal)
            svg = ET.Element("svg", {"xmlns": "http://www.w3.org/2000/svg", "width": "26", "height": "26", "viewBox": "0 0 24 24", "fill": "none", "stroke": "#fff", "stroke-width": "2.2", "stroke-linecap": "round", "stroke-linejoin": "round"})
            for tag, attributes in nodes:
                assert tag in {"path", "line", "circle", "ellipse", "polyline", "polygon", "rect"}
                ET.SubElement(svg, tag, {key: str(value) for key, value in attributes.items() if key != "key"})
            target = root / "ios/Harbor/Assets.xcassets" / f"desktop-{name}.imageset"
            target.mkdir(exist_ok=True)
            vector = ET.tostring(svg, encoding="utf-8") + b"\n"
            (target / "icon.svg").write_bytes(vector)
            contents = {"images": [{"idiom": "universal", "filename": "icon.svg"}], "info": {"author": "xcode", "version": 1}, "properties": {"preserves-vector-representation": True, "template-rendering-intent": "template"}}
            (target / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n", encoding="utf-8")
            records[name] = {"source": relative, "sha256": hashlib.sha256(original).hexdigest(), "svgSha256": hashlib.sha256(vector).hexdigest()}
        license_text = sources.extractfile("package/LICENSE").read().decode()
    (root / "docs/ios/LUCIDE_ICONS_LICENSE.txt").write_text(license_text, encoding="utf-8")
    (root / "docs/ios/library-profile-icon-provenance.json").write_text(json.dumps({"package": "lucide-react", "version": version, "desktopDeclaredVersion": "^0.460.0", "notes": "Original Lucide geometry from the declared beta dependency, not SF Symbols. The reference does not include a lockfile; no claim of its exact resolved dependency version.", "integrity": package["dist"]["integrity"], "files": records}, indent=2) + "\n", encoding="utf-8")
    print(f"Preserved {len(records)} original Lucide geometries with package integrity and provenance.")


if __name__ == "__main__":
    main()
