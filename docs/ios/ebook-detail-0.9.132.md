# Book details and chapter navigation — Desktop 0.9.132

The pinned `src/views/ebook.tsx` supplies the original information rows, volume
grouping, numeric-label parser and chapter ordering. A separate, bridge-free
JavaScriptCore actor executes these pure rules away from the UI. Its source is
5,886 bytes, SHA-256
`7bd0fd5b881f8918f9b87b375c432a793498903b2e83ed939b77dfb221e7cdca`.
Existing catalog and metadata assets are unchanged.

Native book details now include volume selection, chapter search, oldest/newest
sorting, list/grid presentation and thirty-item pagination with show-more and
show-all. Source positions determine numbering direction exactly as Desktop;
Arabic/Persian digits and decimal chapter numbers remain supported. Reader
requests use the original chapter path and publication index, never a sorted
display index. The loaded publication is reused by the reader. Empty sources
show their actual empty state; opening a reader still rejects empty chapters.

Local EPUB and plugin chapter lists load directly. Remote EPUB chapter lists
require an explicit tap, because enumerating their contents downloads the entire
archive. Opening a book detail must not silently download up to 48 MB. PDFs
retain their native page reader.

Information uses Desktop's rating scales, author, first publication, status,
genres, edition/page counts, reader ratings, characters, setting, period and
translation counts, with the installed interface translations. Additional native
ISBN, archive copies, original language and chapter/volume counts remain visible.

Eight new local reference checks passed. Three new native methods cover the
actual JavaScriptCore rules, installed WebKit source volumes/routes/content,
empty sources and requested EPUB chapter identity. Apple execution and the new
phone/tablet interface review remain pending; these are not approved simulator
or physical-device results. Existing approved untouched tests are retained. The
ongoing adaptation run uses the preceding source and does not validate this
increment. No IPA is produced for it.
