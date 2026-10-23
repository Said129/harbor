# Printed passages and chapter-search verification

The original phone recording from run 39877611403, at video time 170 seconds,
shows printed page 12 after the paragraph-30 search jump. That page begins with
the continuation of paragraph 30, followed by paragraphs 31 and 32. The words
`Paragraph 30.` are on the preceding page. The failed UI predicate required
those literal words on the destination page; it did not prove the jump failed.
The frame is preserved under that run's review/search-book-actual-page-170.png.

Keep Desktop's approved resume rule, which chooses the last page whose starting
paragraph is no later than the requested one. Do not change pagination or jump
behavior to satisfy a text-prefix assumption.

Printed pages now announce their actual passage numbers before their rendered
text. The numbers come from the page's row paragraph identities mapped back to
the original block order. Repeated wrapped rows and multiple paragraphs inside
one block produce only one passage announcement; noncontiguous block identifiers
are not mistaken for passage numbers. The existing Desktop translation catalog
supplies the labels. The image, page dimensions, zoom, layout and caches do not
change.

The failed search predicate now requires the specific passage context and real
body text within the visible printed page, including a continuation without its
opening words. The full failure hierarchy is still retained if that check fails.
The two older search UI methods are already running in run 39883561558; do not
repeat them concurrently. Select only any failed/affected search methods after
their original outcomes are collected. This change is not yet Apple-validated.
