"""Original CC0 test pages, natural ZIP ordering and unsafe-path regression."""
from pathlib import Path
from struct import pack
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo
import zlib


def png(red: int, green: int, blue: int) -> bytes:
    def chunk(kind: bytes, value: bytes) -> bytes:
        return pack(">I", len(value)) + kind + value + pack(">I", zlib.crc32(kind + value))

    pixels = (b"\0" + bytes([red, green, blue]) * 4) * 6
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", pack(">IIBBBBB", 4, 6, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(pixels)) + chunk(b"IEND", b"")


def main() -> None:
    target = Path(__file__).resolve().parents[2] / "ios/HarborTests/Fixtures/reader.cbz"
    entries = {"page10.png": png(0, 0, 255), "page2.png": png(0, 255, 0), "page1.png": png(255, 0, 0), "../escape.png": png(0, 0, 0), "__MACOSX/resource.png": png(0, 0, 0)}
    with ZipFile(target, "w") as archive:
        for name, value in entries.items():
            info = ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0)); info.compress_type = ZIP_DEFLATED
            archive.writestr(info, value)
    print(f"Generated original test CBZ: {target.name}, {target.stat().st_size} bytes")


if __name__ == "__main__":
    main()
