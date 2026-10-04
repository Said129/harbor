"""Generate parity tables from reviewed feature groups and real Settings fields."""
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[2]
groups = json.loads((ROOT / "docs/ios/features.json").read_text(encoding="utf-8"))
rows = []
for group in groups:
    source = group["source"]
    if not (ROOT / source).exists():
        raise ValueError(f"Missing Desktop implementation: {source}")
    for feature in group["features"]:
        rows.append(f"| {feature} | Implemented in source; runtime baseline in VALIDATION | Pending | Not Started | `{source}` | — | {group.get('notes', 'Must validate behavior on iPhone')} |")
source = (ROOT / "src/lib/settings/types.ts").read_text(encoding="utf-8")
start = source.index("export type Settings = {")
for match in re.finditer(r"^  (\w+)(?:\?)?:", source[start:], re.M):
    line = source[:start + match.start()].count("\n") + 1
    rows.append(f"| Setting: `{match[1]}` | Declared; verify consumer | Pending | Not Started | `src/lib/settings/types.ts:{line}` | — | Preserve option or document equivalent interaction |")
intro = "# Matriz de paridad Harbor Desktop → iPhone\n\nBase upstream: `0117755855d3f43960bad3f9f62b69ef851d5991`, 2026-10-04. Alcance final incluye todas las entradas. Desktop indica evidencia de código, no certificación de todas las integraciones. States: Not Started, Investigating, Partial, Working, Parity, Blocked. Compilar no basta para Working/Parity; requieren pruebas de comportamiento.\n\n"
intro += f"{len(rows)} entradas: funciones revisadas y cada campo real de Settings. SOURCE_INVENTORY registra además módulos y comandos. No todos los símbolos son funciones de usuario. No se deben presentar stubs upstream como funciones verificadas.\n\n"
intro += "Fuente mantenible: `features.json` y `src/lib/settings/types.ts`. Este generador produce el baseline; NO ejecutarlo sobre una matriz con estados/evidencia editados sin preservar esas actualizaciones.\n\n"
intro += "| Feature | Desktop | iOS | Estado | Implementación Desktop | Implementación iOS | Notas |\n| --- | --- | --- | --- | --- | --- | --- |\n"
(ROOT / "docs/ios/FEATURE_PARITY.md").write_text(intro + "\n".join(rows) + "\n", encoding="utf-8")
print(f"Generated {len(rows)} parity rows")
