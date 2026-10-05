"""Record a public beta checkpoint separately from the historical Desktop base."""
import argparse
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument("--reference", type=Path, required=True)
parser.add_argument("--commit", required=True)
parser.add_argument("--requested-version", required=True)
args = parser.parse_args()
if not re.fullmatch(r"[0-9a-f]{40}", args.commit):
    raise ValueError("The public checkpoint must be a full commit SHA")
reference = args.reference.resolve(strict=True)
package = json.loads((reference / "package.json").read_text(encoding="utf-8"))
settings_path = "src/lib/settings/types.ts"
source = (reference / settings_path).read_text(encoding="utf-8")
start = source.index("export type Settings = {")
end = source.index("\n};", start)
settings = []
for match in re.finditer(r"^  (\w+)(?:\?)?:", source[start:end], re.M):
    settings.append({"id": match[1], "source": settings_path,
                     "line": source[:start + match.start()].count("\n") + 1})
nav_path = "src/chrome/nav-items.tsx"
nav_source = (reference / nav_path).read_text(encoding="utf-8")
nav = re.search(r"export type NavItemId =([\s\S]*?);", nav_source)[1]
rooms = re.findall(r'"([a-z]+)"', nav)
groups = json.loads((ROOT / "docs/ios/features.json").read_text(encoding="utf-8"))
features = [{"id": name, "source": group["source"]} for group in groups
            if (reference / group["source"]).exists() for name in group["features"]]
output = {"requestedVersion": args.requested_version, "publicCheckpointVersion": package["version"],
          "publicCheckpointCommit": args.commit,
          "settingsSourceSha256": hashlib.sha256(source.encode()).hexdigest(),
          "navigationSourceSha256": hashlib.sha256(nav_source.encode()).hexdigest(),
          "navigation": rooms, "features": features, "settings": settings,
          "scopeNote": "Public checkpoint plus owner screenshots; not the exact source of the requested updater release."}
destination = ROOT / "docs/ios"
(destination / "beta-surface.json").write_text(json.dumps(output, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
progress_file = destination / "beta-parity-status.json"
progress = json.loads(progress_file.read_text(encoding="utf-8")) if progress_file.exists() else {}
entries = [("Room: " + room, nav_path, None) for room in rooms]
entries += [(entry["id"], entry["source"], None) for entry in features]
entries += [("Setting: " + entry["id"], entry["source"], entry["line"]) for entry in settings]
valid_states = {"Not Started", "Investigating", "Partial", "Working", "Parity", "Blocked"}
rows = []
for key, path, line in entries:
    evidence = progress.get(key, {})
    state = evidence.get("state", "Not Started")
    if state not in valid_states:
        raise ValueError(f"Invalid state for {key}")
    location = path + (":" + str(line) if line else "")
    cells = [key, state, f"`{location}`", evidence.get("implementation", "Pending"), evidence.get("notes", "Needs implementation and behavior evidence")]
    rows.append("| " + " | ".join(str(cell).replace("|", "/").replace("\n", " ") for cell in cells) + " |")
if progress.keys() - {entry[0] for entry in entries}:
    raise ValueError("Unknown progress keys in beta-parity-status.json")
header = "# Paridad con la beta de Harbor Desktop\n\n"
header += f"Objetivo {args.requested_version}; checkpoint público {package['version']} (`{args.commit}`). La diferencia de versiones se conserva explícitamente. Capturas del propietario y updater oficial completan la referencia visual. No se cambia la base Desktop del repositorio.\n\n"
header += f"{len(entries)} entradas: {len(rooms)} secciones, {len(features)} comportamientos revisados y {len(settings)} ajustes declarados. Los módulos beta adicionales se inspeccionan durante cada implementación; esta lista no implica paridad ni que los stubs Desktop funcionen. Ningún ajuste se excluye automáticamente por su nombre.\n\n"
header += "Estados mantenidos en beta-parity-status.json. Working/Parity necesitan evidencia de comportamiento; código o compilación aislados se registran Partial. La matriz histórica FEATURE_PARITY.md se conserva y no certifica esta beta.\n\n"
header += "| Función | Estado | Fuente beta | Implementación iOS | Evidencia / pendiente |\n| --- | --- | --- | --- | --- |\n"
(destination / "BETA_FEATURE_PARITY.md").write_text(header + "\n".join(rows) + "\n", encoding="utf-8")
print(f"Imported beta {package['version']}: {len(rooms)} rooms, {len(features)} behaviors, {len(settings)} settings")
