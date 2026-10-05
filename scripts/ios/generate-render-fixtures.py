"""Generate small, deterministic 8/10-bit YUV videos for the native render test.

These original test-only color frames are CC0. No downloaded movie, network
service or product fallback is involved. Run from any host with Python 3.
"""
from pathlib import Path
import struct

folder = Path(__file__).resolve().parents[2] / "ios/HarborTests/Fixtures"
folder.mkdir(parents=True, exist_ok=True)
width, height, frames = 64, 32, 36
# Limited-range BT.601: red on the left, green on the right.
for depth in (8, 10):
    scale = 1 << (depth - 8)
    pack = (lambda n: bytes([n])) if depth == 8 else (lambda n: struct.pack("<H", n))
    planes = []
    for columns, rows, colors in ((width, height, (81, 145)),
                                  (width // 2, height // 2, (90, 54)),
                                  (width // 2, height // 2, (240, 34))):
        row = pack(colors[0] * scale) * (columns // 2) + pack(colors[1] * scale) * (columns // 2)
        planes.append(row * rows)
    chroma = "420jpeg" if depth == 8 else "420p10"
    path = folder / f"render-{depth}bit.y4m"
    with path.open("wb") as output:
        output.write(f"YUV4MPEG2 W{width} H{height} F6:1 Ip A1:1 C{chroma}\n".encode("ascii"))
        for _ in range(frames):
            output.write(b"FRAME\n" + b"".join(planes))
    print(f"Generated {path.name}: {path.stat().st_size} bytes")
