"""Obtain the original interface font directly for this application build.

Fontshare permits application embedding. The upstream font is not converted or
distributed as a standalone font in the public source repository.
"""
import argparse
import hashlib
from io import BytesIO
from pathlib import Path
from urllib.request import Request, urlopen
from zipfile import ZipFile

SOURCE = "https://api.fontshare.com/v2/fonts/download/switzer"
FONT_ENTRY = "Switzer_Complete/Fonts/TTF/Switzer-Variable.ttf"
LICENSE_ENTRY = "Switzer_Complete/License/FFL.txt"
SHA256 = "373c2d2ad8f1f811ca58ae725e9591db2e72cf726dc6e8066cd7f64b4c283cdf"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    if args.archive:
        if args.archive.stat().st_size > 32 * 1024 * 1024:
            raise ValueError("Unexpected font archive size")
        payload = args.archive.read_bytes()
    else:
        with urlopen(Request(SOURCE, headers={"User-Agent": "Harbor-iPhone-build"}), timeout=45) as response:
            payload = response.read(32 * 1024 * 1024 + 1)
        if len(payload) > 32 * 1024 * 1024:
            raise ValueError("Unexpected font archive size")
    with ZipFile(BytesIO(payload)) as archive:
        if archive.getinfo(FONT_ENTRY).file_size > 2 * 1024 * 1024 or archive.getinfo(LICENSE_ENTRY).file_size > 128 * 1024:
            raise ValueError("Unexpected font resource size")
        font = archive.read(FONT_ENTRY)
        license_text = archive.read(LICENSE_ENTRY)
    if hashlib.sha256(font).hexdigest() != SHA256:
        raise ValueError("The original pinned font has changed; review before updating the checksum")
    for relative, data in [("ios/Harbor/Fonts/Switzer.ttf", font), ("ios/Harbor/Licenses/Switzer-FFL.txt", license_text)]:
        output = root / relative
        if output.resolve() != output.absolute():
            raise ValueError("Refusing a redirected build resource")
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(data)
    print(f"Original Switzer interface font verified: {len(font)} bytes, SHA256 {SHA256}")


if __name__ == "__main__":
    main()
