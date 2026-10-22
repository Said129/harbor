# Reading navigation repair against Desktop 0.9.132

Original Apple results were retained from runs 39763655130, 39768078426 and 39770691335. All seventeen new model tests passed; fourteen UI routes failed.
The later two compilers confirmed that the EBookRelatedView concurrency warning
was fixed. These results do not approve complete Desktop parity or an IPA.

The failure hierarchies established the following causes:

- Reading repository downloads omitted the explicit local-network flag. The
  owned server received no bulk source requests; every entry failed immediately.
  Repository and entry downloads now use the same bounded local access as reading
  providers. HTTP is accepted explicitly for reading repositories; the ordinary
  streaming-plugin URL and network policies retain their defaults.
- Manga detail reported the missing-connection message despite its parent having
  installed reading sources. Every Manga detail destination and the chapter
  reader now receive their parent's reading manager explicitly.
- A parent `ebook-chapters` accessibility identifier replaced the identifiers of
  the chapter controls. Removing that inherited identifier preserves each
  control's identifier and accessibility behavior.
- The reader's failed iPad hierarchy gave its scroll view a zero-sized frame.
  Reader and scroll view now explicitly fill the available area. Actual rendered
  text, brightness and font interfaces still require the affected UI rerun.
- The UI harness queried hittability on unrealized lazy cells, assumed an
  offscreen catalog card existed, and prepended `{}` to a text editor instead of
  replacing its content. It now scrolls before checking hittability, enters
  Discover directly, and selects the entire editor value before replacing it.
  The replacement is checked before saving. Visible toolbar taps use their actual
  observed frame to avoid iPad's failed accessibility scroll action.
- The original Desktop `sourceFallback` can display the source item's Latin slug
  when the alternative title is Arabic. The owned fixture therefore displays
  `owned`. Source switching is verified through selected state and actual chapter
  content, preserving Desktop's behavior.

The new `reading-navigation` selection runs only two new repository contracts,
two necessary fresh-device preparations and the ten failed source/catalog/HTML
routes. The seventeen passed model cases remain excluded. Four affected book
detail and display routes remain pending a separate new-font validation scope.
The local fixture holds downloads for five seconds solely to observe real
network progress; the production app adds no delay.

No IPA is built by these validation selections.
