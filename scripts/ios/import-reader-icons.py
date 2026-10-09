"""Preserve Desktop's original PNG reader controls in native asset catalogs."""
import hashlib
import json
from pathlib import Path
import shutil
import sys

reference = Path(sys.argv[1]).resolve(strict=True)
root = Path(__file__).resolve().parents[2]
originals = reference / "public/reader-icons"
provenance_path = root / "docs/ios/beta-vector-provenance.json"
provenance = json.loads(provenance_path.read_text(encoding="utf-8"))
records = {}
for source in sorted(originals.glob("*.png")):
    target = root / "ios/Harbor/Assets.xcassets" / ("reader-" + source.stem + ".imageset")
    target.mkdir(exist_ok=True)
    shutil.copyfile(source, target / "icon.png")
    (target / "Contents.json").write_text(json.dumps({"images": [{"idiom": "universal", "filename": "icon.png"}], "info": {"author": "xcode", "version": 1}, "properties": {"template-rendering-intent": "original"}}, indent=2) + "\n", encoding="utf-8")
    records[source.relative_to(reference).as_posix()] = hashlib.sha256(source.read_bytes()).hexdigest()
provenance["readerIcons"] = records
provenance_path.write_text(json.dumps(provenance, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(f"Preserved {len(records)} original PNG reader icons without image edits.")
