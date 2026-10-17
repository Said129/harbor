"""Import literal ESPN league metadata from the reviewed Desktop checkpoint."""
import hashlib
import json
from pathlib import Path
import re
import sys

reference = Path(sys.argv[1]).resolve(strict=True)
root = Path(__file__).resolve().parents[2]
paths = ["src/lib/sports/espn-leagues.ts", "src/lib/sports/leagues-extra.ts", "src/lib/sports/regional-sports-catalog.ts", "src/lib/sports/additional-sports-catalog.ts"]
leagues = {}
hashes = {}
for path in paths:
    text = (reference / path).read_text(encoding="utf-8")
    hashes[path] = hashlib.sha256(text.encode()).hexdigest()
    constants = dict(re.findall(r'const\s+(\w+)\s*=\s*"(https://[^"]+)"', text))
    for name, template in re.findall(r'const\s+(\w+)\s*=\s*`([^`]+)`', text):
        for key, value in constants.items():
            template = template.replace("${" + key + "}", value)
        if template.startswith("https://") and "${" not in template:
            constants[name] = template
    for block in re.findall(r'\{\s*key:\s*"[^"]+"[\s\S]*?\n\s*\}', text):
        fields = dict(re.findall(r'(key|labelEn|path|group):\s*"([^"]+)"', block))
        if not all(key in fields for key in ("key", "labelEn", "path", "group")) or not re.fullmatch(r"[a-z-]+/[A-Za-z0-9_.-]+", fields["path"]):
            continue
        logo_match = re.search(r'logo:\s*("[^"]*"|`[^`]*`|[A-Z_]+)', block)
        logo = logo_match[1] if logo_match else ""
        if logo.startswith(('"', '`')):
            logo = logo[1:-1]
            for key, value in constants.items():
                logo = logo.replace("${" + key + "}", value)
        else:
            logo = constants.get(logo, "")
        leagues[fields["key"]] = {"id": fields["key"], "title": fields["labelEn"], "path": fields["path"], "group": fields["group"], "logo": logo if logo.startswith("https://") and "${" not in logo else None}
    if path.endswith("espn-leagues.ts"):
        for key, label, endpoint, logo in re.findall(r'\["(\w+)", "([^"]+)", "([a-z0-9_.]+)", "(\d*)"\]', text):
            leagues[key] = {"id": key, "title": label, "path": "soccer/" + endpoint, "group": "soccer", "logo": constants["LL"] + "/" + logo + ".png" if logo else None}
assert {"ROSHN", "EPL", "UCL", "NBA", "NFL", "LALIGA"} <= leagues.keys(), "Missing original core leagues"
target = root / "ios/Harbor/SportsLeagues.json"
target.write_text(json.dumps(list(leagues.values()), indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
provenance_path = root / "docs/ios/beta-vector-provenance.json"
provenance = json.loads(provenance_path.read_text(encoding="utf-8")); provenance["sportsCatalog"] = {"sourceHashes": hashes, "count": len(leagues), "scope": "Literal ESPN leagues and original soccer tuple expansions; provider-only and other generated catalogs remain separate."}
provenance_path.write_text(json.dumps(provenance, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(f"Imported {len(leagues)} original league definitions; no events or results are bundled.")
