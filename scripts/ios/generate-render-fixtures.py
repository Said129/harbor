"""Generate small 8/10-bit MP4 videos for the native render test.

These original test-only color frames are CC0. No downloaded movie, network
service or product fallback is involved. Regeneration requires Python 3 and
FFmpeg with libx264/libx265: python generate-render-fixtures.py --ffmpeg PATH.
The committed fixtures play offline through MPVKit's normal H.264/HEVC stack;
the packaged multimedia build does not recognize the raw Y4M inputs.
"""
import argparse
from pathlib import Path
import struct
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--ffmpeg", default="ffmpeg")
args = parser.parse_args()
folder = Path(__file__).resolve().parents[2] / "ios/HarborTests/Fixtures"
folder.mkdir(parents=True, exist_ok=True)
width, height, frames = 64, 32, 180
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
    path = folder / f"render-{depth}bit.mp4"
    with tempfile.TemporaryDirectory(prefix="harbor-render-") as temporary:
        raw = Path(temporary) / "colors.y4m"
        with raw.open("wb") as output:
            output.write(f"YUV4MPEG2 W{width} H{height} F6:1 Ip A1:1 C{chroma}\n".encode("ascii"))
            for _ in range(frames):
                output.write(b"FRAME\n" + b"".join(planes))
        codec = "libx264" if depth == 8 else "libx265"
        pixel_format = "yuv420p" if depth == 8 else "yuv420p10le"
        extra = [] if depth == 8 else ["-x265-params", "pools=none:frame-threads=1:log-level=error", "-tag:v", "hvc1"]
        subprocess.run([args.ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", str(raw),
                        "-an", "-c:v", codec, "-preset", "ultrafast", "-crf", "18", "-pix_fmt", pixel_format,
                        *extra, "-colorspace", "smpte170m", "-color_trc", "bt709", "-color_primaries", "smpte170m",
                        "-movflags", "+faststart", str(path)], check=True)
    print(f"Generated {path.name}: {path.stat().st_size} bytes")
