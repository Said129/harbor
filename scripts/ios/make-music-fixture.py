"""Original CC0 stereo PCM fixture, copied into tests only, never product assets."""
from pathlib import Path
import math
import struct
import wave

target = Path(__file__).resolve().parents[2] / "ios/HarborTests/Fixtures/owned-tone.wav"
rate = 44_100
samples = bytearray()
for frame in range(rate * 8):
    samples.extend(struct.pack("<hh", *(int(3_000 * math.sin(2 * math.pi * hz * frame / rate)) for hz in [220, 330])))
with wave.open(str(target), "wb") as output:
    output.setnchannels(2)
    output.setsampwidth(2)
    output.setframerate(rate)
    output.writeframes(samples)
print("Generated original eight-second PCM audio for native tests")
