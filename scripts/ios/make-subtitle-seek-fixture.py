"""Mux our existing CC0 H.264 frames, PCM and timed text into a tiny seek fixture.

No external media or FFmpeg install is needed. The input has one video track,
no B frames and contiguous samples (generate-render-fixtures.py).
"""
from pathlib import Path
import math
import struct

folder = Path(__file__).resolve().parents[2] / "ios/HarborTests/Fixtures"
source = (folder / "render-8bit.mp4").read_bytes()


def box(kind):
    offset = source.index(kind) - 4
    size = struct.unpack_from(">I", source, offset)[0]
    return source[offset + 8:offset + size]


def element(tag, value):
    tag_bytes = bytes.fromhex(tag)
    length = len(value)
    count = next(n for n in range(1, 9) if length < (1 << (7 * n)) - 1)
    return tag_bytes + ((1 << (7 * count)) | length).to_bytes(count, "big") + value


def uint(tag, value):
    return element(tag, value.to_bytes(max(1, (value.bit_length() + 7) // 8), "big"))


def text(tag, value):
    return element(tag, value.encode())


def track(number, kind, codec, extra=b""):
    return element("AE", uint("D7", number) + uint("73C5", number) + uint("83", kind)
                   + uint("9C", 0) + text("86", codec) + extra)


sizes = box(b"stsz")
fixed, count = struct.unpack_from(">II", sizes, 4)
sizes = [fixed] * count if fixed else list(struct.unpack_from(">" + "I" * count, sizes, 12))
offset = struct.unpack_from(">I", box(b"stco"), 8)[0]
frames = []
for size in sizes:
    frames.append(source[offset:offset + size])
    offset += size
assert len(frames) == 180 and sum(sizes) == len(box(b"mdat"))
sync = box(b"stss")
keyframes = set(struct.unpack_from(">" + "I" * struct.unpack_from(">I", sync, 4)[0], sync, 8))
video = element("E0", uint("B0", 64) + uint("BA", 32))
audio = element("E1", element("B5", struct.pack(">d", 8000)) + uint("9F", 1) + uint("6264", 16))
tracks = element("1654AE6B", track(1, 1, "V_MPEG4/ISO/AVC", element("63A2", box(b"avcC")) + video)
                 + track(2, 2, "A_PCM/INT/LIT", audio) + track(3, 17, "S_TEXT/UTF8"))
info = element("1549A966", uint("2AD7B1", 1_000_000) + element("4489", struct.pack(">d", 30_000))
               + text("4D80", "Harbor owned fixture") + text("5741", "Harbor owned fixture"))
packets = []
for index, frame in enumerate(frames):
    packets.append((round(index * 1000 / 6), 1, frame, index + 1 in keyframes, None))
for second in range(30):
    pcm = b"".join(struct.pack("<h", int(1800 * math.sin(2 * math.pi * 220 * (second + n / 8000)))) for n in range(8000))
    packets.append((second * 1000, 2, pcm, True, None))
for index in range(7):
    packets.append((index * 4000, 3, f"EMBEDDED CUE {index}".encode(), True, 3500))
clusters = []
for start in range(0, 30_000, 4000):
    data = uint("E7", start)
    for at, number, value, keyframe, duration in sorted(packets, key=lambda p: (p[0], p[1])):
        if start <= at < start + 4000:
            block = bytes([0x80 | number]) + struct.pack(">hB", at - start, 0x80 if keyframe and duration is None else 0) + value
            data += element("A3", block) if duration is None else element("A0", element("A1", block) + uint("9B", duration))
    clusters.append(element("1F43B675", data))
header = element("1A45DFA3", uint("4286", 1) + uint("42F7", 1) + uint("42F2", 4) + uint("42F3", 8)
                 + text("4282", "matroska") + uint("4287", 4) + uint("4285", 2))
target = folder / "owned-subtitle-seek.mkv"
target.write_bytes(header + element("18538067", info + tracks + b"".join(clusters)))
print(f"Generated {target.name}: {target.stat().st_size} bytes")
