# Manual Manga and Books sources

Reference: Desktop 0.9.132,
`0834340cec5531650bfe78cd628628702e636987`. The generated program extracts the
original HTML config parsers, source identifiers, CSS selection, pagination,
chapter mapping, content cleaning and Manga favicon detection from five pinned
reference inputs. It does not substitute the worker's restricted CSS engine.

Manual configurations run with the full WebKit DOM and the bundled first-party
factories. Configurations are JSON data; no supplied script is evaluated in the
page. Installed script plugins retain the original isolated worker path. Both
paths reuse the existing native transport, request limits, startup/operation
deadlines, scoped cancellation, pending replies and worker retirement.

The trusted HTML program is 19,762 UTF-8 bytes, SHA-256
`03037e3519b6c30e1d7d3c494f705fd94b5346875d60f6aea5fe977b5ce1d437`.
Its source IDs and book routes follow Desktop, including encoded relative book
identifiers. Image requests inherit the manual source's configured headers.

Manga and Books source management now has Add source and Edit actions. The native
editor supports source name, logo, language and the original JSON selector
configuration. Manga uses the original bounded favicon lookup when no logo is
specified. Save/Cancel remain visible above the mobile keyboard. Existing native
source toggles and confirmed removal apply to these sources. Editing a base URL
replaces the former ID; deleting a manual source removes its stored configuration
from the local repository as well. Reader source-management links open the
appropriate reading kind directly.

Executed local checks: nine provider fixtures, two request checks, two pagination
checks, three invalid-config cases, two favicon cases and six trusted-host bridge
cases. The host cases exercise initialization, ordered JSON, cancellation with
independent replies, disposal, invalid input and config-as-data isolation. These
checks do not repeat existing normal-worker suites or establish native approval.

The selected native block has four new model tests, two fresh device preparations
and two new phone/tablet UI routes, requiring twelve captures. It will verify the
original fixtures in the actual WebKit DOM, persistence/editing/removal, headers,
configuration rejection, cancellation/owner retirement and ordinary reader paths.
The exact workflow shell and owned loopback HTML/image routes passed local
preflight. Apple SDK execution and screenshot/motion review remain pending.

The complete Desktop port remains active. No IPA is packaged by this validation
block; final delivery remains one consolidated validated IPA.
