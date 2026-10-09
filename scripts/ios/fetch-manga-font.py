"""Fetch the original Manga title font for the owner's personal iPhone build.

The font's embedded notice restricts it to personal use. Its bytes are fetched
from the pinned original source, not redistributed as a standalone repo asset.
"""
import argparse
import hashlib
from pathlib import Path
from urllib.request import Request, urlopen

SOURCE = "https://raw.githubusercontent.com/harborstremio/harbor/19ddc311a397eb3483b5c978d2cf2bbb3f7f479f/src/assets/fonts/qr-ames-beta.otf"
SHA256 = "5c593a025281aeb2f03aacaa081dc3b206d4dff41f0b5bb55edc49b5dff62dd4"
NOTICE = "QR Ames by Abay Emes, QR Type\nBeta Version - Free for personal use only\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--font", type=Path)
    args = parser.parse_args()
    if args.font:
        if args.font.stat().st_size > 128 * 1024:
            raise ValueError("Unexpected original font size")
        data = args.font.read_bytes()
    else:
        with urlopen(Request(SOURCE, headers={"User-Agent": "Harbor-iPhone-build"}), timeout=30) as response:
            data = response.read(128 * 1024 + 1)
    if len(data) != 29152 or not data.startswith(b"OTTO") or hashlib.sha256(data).hexdigest() != SHA256:
        raise ValueError("The original Manga font changed; review before replacing it")
    root = Path(__file__).resolve().parents[2]
    for relative, payload in [("ios/Harbor/Fonts/QRAmesBeta.otf", data), ("ios/Harbor/Licenses/QR-Ames-personal-use.txt", NOTICE.encode())]:
        output = root / relative
        if output.resolve() != output.absolute():
            raise ValueError("Refusing a redirected build resource")
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(payload)
    print(f"Original personal-use Manga font verified: {len(data)} bytes, SHA256 {SHA256}")


if __name__ == "__main__":
    main()
