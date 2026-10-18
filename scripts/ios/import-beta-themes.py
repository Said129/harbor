"""Copy the eight source palettes, converting CSS colors to native sRGB."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re


def rgba(value: str) -> list[float]:
    if value.startswith("#"):
        raw = value[1:]
        if len(raw) == 3:
            raw = "".join(c * 2 for c in raw)
        if len(raw) == 6:
            raw += "ff"
        return [round(int(raw[i:i + 2], 16) / 255, 8) for i in range(0, 8, 2)]
    if value.startswith("rgba("):
        r, g, b, a = map(float, value[5:-1].split(","))
        return [r / 255, g / 255, b / 255, a]
    match = re.fullmatch(r"oklch\((\S+) (\S+) (\S+?)(?: / (\S+))?\)", value)
    if not match:
        raise ValueError(f"Unsupported source color {value}")
    light, chroma, hue = map(float, match.groups()[:3])
    a, b = chroma * math.cos(math.radians(hue)), chroma * math.sin(math.radians(hue))
    l = (light + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m = (light - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s = (light - 0.0894841775 * a - 1.2914855480 * b) ** 3
    channels = [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s]
    return [round(max(0, min(1, 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055)), 8) for c in channels] + [float(match[4] or 1)]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--reference", type=Path, required=True)
    args = parser.parse_args()
    source = (args.reference / "src/lib/theme.ts").read_text(encoding="utf-8")
    area = source.split("export const THEME_PRESETS:", 1)[1].split("\n};", 1)[0]
    palettes = []
    for match in re.finditer(r'    id: "([^"]+)",\n    name: "([^"]+)",[\s\S]*?    tokens: \{([\s\S]*?)\n    \}', area):
        colors = dict(re.findall(r'"--color-([^"]+)": "([^"]+)"', match[3]))
        palettes.append({"id": match[1], "name": match[2], "tokens": {key: rgba(value) for key, value in colors.items()}, "sourceColors": colors})
    if len(palettes) != 8:
        raise ValueError("Expected the eight reviewed base palettes")
    root = Path(__file__).resolve().parents[2]
    output = {"source": "src/lib/theme.ts", "sha256": hashlib.sha256(source.encode()).hexdigest(), "palettes": palettes}
    target = root / "ios/Harbor/DesktopThemes.json"
    target.write_text(json.dumps(output, indent=2) + "\n", encoding="utf-8")
    print(f"Imported {len(palettes)} original palettes")


if __name__ == "__main__":
    main()
