"""Generate parity tables from reviewed feature groups and real Settings fields."""
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[2]
groups = json.loads((ROOT / "docs/ios/features.json").read_text(encoding="utf-8"))
progress = json.loads((ROOT / "docs/ios/parity-status.json").read_text(encoding="utf-8"))
states = {"Not Started", "Investigating", "Partial", "Working", "Parity", "Blocked"}
rows = []
used = set()


def row(feature, desktop, source, notes):
    evidence = progress.get(feature, {})
    used.add(feature)
    state = evidence.get("state", "Not Started")
    if state not in states:
        raise ValueError(f"Invalid parity state for {feature}: {state}")
    cells = [feature, desktop, evidence.get("ios", "Pending"), state, f"`{source}`", evidence.get("implementation", "—"), evidence.get("notes", notes)]
    if any("|" in cell or "\n" in cell for cell in cells):
        raise ValueError(f"Invalid table cell for {feature}")
    rows.append("| " + " | ".join(cells) + " |")


for group in groups:
    source = group["source"]
    if not (ROOT / source).exists():
        raise ValueError(f"Missing Desktop implementation: {source}")
    for feature in group["features"]:
        row(feature, "Implemented in source; runtime baseline in VALIDATION", source, group.get("notes", "Must validate behavior on iPhone"))
source = (ROOT / "src/lib/settings/types.ts").read_text(encoding="utf-8")
start = source.index("export type Settings = {")
for match in re.finditer(r"^  (\w+)(?:\?)?:", source[start:], re.M):
    line = source[:start + match.start()].count("\n") + 1
    row(f"Setting: `{match[1]}`", "Declared; verify consumer", f"src/lib/settings/types.ts:{line}", "Preserve option or document equivalent interaction")
if progress.keys() - used:
    raise ValueError(f"Unknown features in parity-status.json: {progress.keys() - used}")
intro = "# Matriz de paridad Harbor Desktop → iPhone\n\nBase upstream: `0117755855d3f43960bad3f9f62b69ef851d5991`, 2026-10-04. Alcance final incluye todas las entradas. Desktop indica evidencia de código, no certificación de todas las integraciones. States: Not Started, Investigating, Partial, Working, Parity, Blocked. Compilar no basta para Working/Parity; requieren pruebas de comportamiento.\n\n"
intro += f"{len(rows)} entradas: funciones revisadas y cada campo real de Settings. SOURCE_INVENTORY registra además módulos y comandos. No todos los símbolos son funciones de usuario. No se deben presentar stubs upstream como funciones verificadas.\n\n"
intro += "Fuentes mantenibles: `features.json`, `src/lib/settings/types.ts` y `parity-status.json` para los estados y evidencia iOS. Actualizar progreso en ese JSON y ejecutar `python scripts/ios/update-parity.py`; regenerar conserva el progreso. Los estados Partial actuales tienen código y pruebas de contratos desde Windows, pero esperan validación Swift/enlace Apple y comportamiento físico. Ver VALIDATION.md.\n\n"
intro += "| Feature | Desktop | iOS | Estado | Implementación Desktop | Implementación iOS | Notas |\n| --- | --- | --- | --- | --- | --- | --- |\n"
(ROOT / "docs/ios/FEATURE_PARITY.md").write_text(intro + "\n".join(rows) + "\n", encoding="utf-8")
print(f"Generated {len(rows)} parity rows")
