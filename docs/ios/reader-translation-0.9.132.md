# Original chapter translation on iOS

Reference: `0834340cec5531650bfe78cd628628702e636987`,
`src/lib/ebook/translation.ts`, its exact instruction file and language labels.
The instruction document is application prompt data, not development instructions.

The asset builder verifies all three original SHA-256 inputs and extracts the
original request body, FNV/UTF-16 cache identity, SSE consumption and final XML
validation. The original 32 KB system prompt is retained verbatim. These pure
rules execute in JavaScriptCore without script bridges or arbitrary networking.
The native transport posts only to DeepSeek over HTTPS, rejects redirects and
does not keep authentication in cookies, URL caches, files or diagnostic logs.

Sources metadata settings and reader settings expose the sixteen target
languages, original Flash/Pro models, secure own-key entry, automatic toggle,
test and save. Configuration is stored in the profile's Keychain record. The
mobile save action preserves the chosen automatic toggle, so saving other
settings can also persist an explicit off choice. Testing uses the same original
sample sentence and does not populate a chapter cache.

Opening a text chapter checks its durable profile cache before the automatic
toggle/key, as Desktop does. An enabled configuration can translate that chapter;
manual translation is available from the reader footer. The reader reports
progress/ETA and can switch between original and translation. It retains the
source book, volume/chapter identities, illustrations and every returned
paragraph. Corresponding text blocks keep original anchors; extra paragraphs
receive new unique anchors. Cancellation, invalid or truncated output preserves
the displayed original. A completed translation is written atomically with file
protection, keyed by original text/title, target, model and instruction version.
An in-flight request is coalesced within the profile client.

Local execution covers seven original response cases and four cache identities,
including multilingual split XML, fenced output, empty title fallback, truncation,
filtered output, incomplete and empty translations. Five NEW native contracts
add request/header checks through an owned transport, real durable/profile
storage, cancellation, coalescing, image/anchor preservation and Keychain settings.
Two NEW ordinary phone/tablet UI routes use preseeded owned cached translations
without any API key or paid request. They cover original/translated reading,
model/language/automatic choices and persistence after relaunch; twelve captures.

Apple compilation, native execution and rendered phone/tablet evidence remain
pending for this increment until original results are collected. The HTTP service
has not been tested with a user's paid DeepSeek account. No key is bundled and
no IPA is created by the validation selection. Prior approved tests remain
retained; the reader and bookmark runs continue on their immutable older sources.

The two bookmark native contracts passed in run 39935330648 at source d0ea6d2.
The original tree and Xcode log agree, with archive SHA-256
`7804060edbda10dcce98c35771444b8bbe829d3175f0dc75f85c2ddc20b5a2c0`.
They are retained unchanged, bringing the recent native block total to thirty;
their independent phone/tablet UI methods are still pending.

Annotations and complete Edge narration remain separate full-port requirements;
this increment does not complete the reader or the overall 1:1 port.
