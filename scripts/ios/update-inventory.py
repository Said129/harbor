"""Refresh the upstream source inventory without inventing feature support."""
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
paths = subprocess.check_output(["git", "ls-files", "src", "src-tauri/src", "harbor-core/src"], cwd=ROOT, text=True).splitlines()
rows = []
commands = []
settings = []
for name in paths:
    path = ROOT / name
    if path.suffix not in {".rs", ".ts", ".tsx"}:
        continue
    source = path.read_text(encoding="utf-8")
    if name.startswith(("src/lib/", "src/views/", "src-tauri/src/", "harbor-core/src/")):
        exports = re.findall(r"^(?:export (?:async )?function|pub(?:\([^)]*\))? (?:async )?fn)\s+(\w+)", source, re.M)
        rows.append(f"| `{name}` | {len(source.splitlines())} | {', '.join('`' + s + '`' for s in exports) or 'Module / UI / types'} |")
    for match in re.finditer(r"#\[tauri::command[^\]]*\]\s*(?:pub )?(?:async )?fn\s+(\w+)", source):
        commands.append(f"| `{match[1]}` | `{name}` |")
    if name == "src/lib/settings/types.ts":
        start = source.index("export type Settings = {")
        for line_number, line in enumerate(source[:start].splitlines(), 1):
            pass
        for match in re.finditer(r"^  (\w+)(?:\?)?:", source[start:], re.M):
            line_number = source[:start + match.start()].count("\n") + 1
            settings.append(f"| `{match[1]}` | `src/lib/settings/types.ts:{line_number}` | Not Started |")
output = "# Inventario de fuentes upstream\n\nBase: `0117755855d3f43960bad3f9f62b69ef851d5991`. Regenerar con `python scripts/ios/update-inventory.py`. Los símbolos documentan cobertura de inspección, no certifican funcionamiento Desktop ni paridad iOS. La matriz humana descompone las funciones por comportamiento.\n\n"
output += f"{len(rows)} módulos/vistas, {len(commands)} comandos Tauri, {len(settings)} campos de Settings.\n\n"
output += "## Módulos y funciones públicas\n\n| Archivo | Líneas | Funciones / clase de módulo |\n| --- | --- | --- |\n" + "\n".join(rows)
output += "\n\n## Comandos IPC Desktop\n\n| Comando | Implementación |\n| --- | --- |\n" + "\n".join(commands)
output += "\n\n## Ajustes individuales que deben mapearse\n\nCampos declarados; algunas opciones Desktop requieren verificación de sus consumidores. No se omiten por no tener equivalente móvil todavía.\n\n| Ajuste | Fuente | Estado iOS |\n| --- | --- | --- |\n" + "\n".join(settings) + "\n"
(ROOT / "docs/ios/SOURCE_INVENTORY.md").write_text(output, encoding="utf-8")
print(f"Inventoried {len(rows)} modules, {len(commands)} commands, {len(settings)} settings")
