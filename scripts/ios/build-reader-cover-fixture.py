"""Create a small owned EPUB with a recognizable embedded geometric cover."""
from pathlib import Path
import struct
import zlib
import zipfile

root = Path(__file__).resolve().parents[2]
directory = root / 'ios/HarborTests/Fixtures'
width, height = 160, 240
rows = bytearray()
for y in range(height):
    rows.append(0)
    for x in range(width):
        color = (16, 30, 52)
        if 12 <= x < 148 and 12 <= y < 228: color = (21, 158, 174)
        if 25 <= x < 135 and 40 <= y < 185: color = (248, 192, 68)
        if 40 <= x < 120 and 61 <= y < 160: color = (245, 240, 219)
        if 48 <= x < 112 and y in range(80, 90): color = (16, 30, 52)
        if 48 <= x < 100 and y in range(110, 120): color = (16, 30, 52)
        rows.extend(color)
def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
png += chunk(b'IDAT', zlib.compress(rows, 9)) + chunk(b'IEND', b'')
with zipfile.ZipFile(directory / 'reader.epub') as original:
    entries = {name: original.read(name) for name in original.namelist()}
opf = entries['OPS/book.opf'].decode('utf-8')
assert 'Harbor reader fixture' in opf
opf = opf.replace('Harbor reader fixture', 'Owned cover book')
opf = opf.replace('</metadata>', '<meta name="cover" content="owned-cover"/></metadata>')
opf = opf.replace('</manifest>', '<item id="owned-cover" href="owned-cover.png" properties="cover-image" media-type="image/png"/></manifest>')
entries['OPS/book.opf'] = opf.encode('utf-8'); entries['OPS/owned-cover.png'] = png
destination = directory / 'reader-cover.epub'
with zipfile.ZipFile(destination, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for name, data in entries.items():
        info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_STORED if name == 'mimetype' else zipfile.ZIP_DEFLATED
        archive.writestr(info, data)
with zipfile.ZipFile(destination) as archive: assert archive.testzip() is None
print('Owned cover EPUB:', destination.stat().st_size, 'bytes; embedded PNG', width, height)
