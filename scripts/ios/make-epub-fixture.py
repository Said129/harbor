"""Generate the original CC0 two-section reader regression input, tests only."""
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZIP_STORED, ZipFile, ZipInfo


def main() -> None:
    target = Path(__file__).resolve().parents[2] / "ios/HarborTests/Fixtures/reader.epub"
    entries = {
        "mimetype": "application/epub+zip",
        "META-INF/container.xml": '<?xml version="1.0"?><container><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>',
        "OPS/book.opf": '<package xmlns:dc="http://purl.org/dc/elements/1.1/"><metadata><dc:title>Harbor reader fixture</dc:title><dc:creator>Harbor tests</dc:creator><dc:language>en</dc:language></metadata><manifest><item id="nav" href="nav.xhtml" properties="nav" media-type="application/xhtml+xml"/><item id="second" href="second.xhtml" media-type="application/xhtml+xml"/><item id="first" href="first.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="first"/><itemref idref="second"/></spine></package>',
        "OPS/nav.xhtml": '<html><body><nav><a href="first.xhtml">First section</a><a href="second.xhtml">Second section</a></nav></body></html>',
        "OPS/first.xhtml": '<html><head><title>Not reader text</title><script>Forbidden</script></head><body><h1>First section</h1><p>One <strong>two</strong> three &amp; four.</p><script>Forbidden body</script><p><![CDATA[Literal <text>]]></p><img src="https://outside.invalid/image.png" alt="No remote fetch"/></body></html>',
        "OPS/second.xhtml": '<html><body><h1>Second section</h1><p>Five six seven.</p></body></html>',
    }
    target.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(target, "w") as archive:
        for name, contents in entries.items():
            info = ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = ZIP_STORED if name == "mimetype" else ZIP_DEFLATED
            archive.writestr(info, contents.encode("utf-8"))
    print(f"Generated original test EPUB: {target.name}, {target.stat().st_size} bytes")


if __name__ == "__main__":
    main()
