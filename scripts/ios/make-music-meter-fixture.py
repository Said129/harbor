"""Owned stereo tones and silence for measured playback-clock validation."""
from pathlib import Path
import math
import struct
import wave

root = Path(__file__).resolve().parents[2]
output = root / "ios/HarborTests/Fixtures/owned-meter-tones.wav"
rate = 48_000
frames = bytearray()
for sample in range(rate * 12):
    time = sample / rate
    if 4 <= time < 6:
        left = right = 0
    else:
        low, high = (500, 1000) if time < 4 else (120, 2000)
        left = int(32767 * 0.25 * math.sin(2 * math.pi * low * time))
        right = int(32767 * 0.125 * math.sin(2 * math.pi * high * time))
    frames.extend(struct.pack("<hh", left, right))
with wave.open(str(output), "wb") as sound:
    sound.setnchannels(2)
    sound.setsampwidth(2)
    sound.setframerate(rate)
    sound.writeframes(frames)
print(f"Owned 12-second stereo fixture: {output.name}, {output.stat().st_size} bytes")
