# Reading repository actions and consolidated validation

Reading repositories now support Install all, Update all and confirmed removal
of installed entries while retaining the repository. Installation shows actual
per-entry progress, allows cancellation and keeps successful entries if another
entry fails. Individual failures remain visible on their rows. A batch with no
successful installation reports its failure. All mutations share the existing
owner-scoped transaction and cancellation guards.

Desktop reference: 0.9.132, `src/views/settings/plugins-panel/repo-group.tsx` and
`src/lib/manga/sources/mangayomi/repo.ts` at
`0834340cec5531650bfe78cd628628702e636987`.

Run 39666426032 failed during simulator compilation, before any native or UI
test executed. Its original compiler ZIP identifies an implicit catch binding
shadowing the view's error property. Both affected reading views now assign
`self.error`. The previous cover expression was accepted. Run 39670150636
contained the identical compiler error and was cancelled before test execution.

The consolidated selection contains 13 new, unexecuted or actually failed model
cases, two fresh device preparations and two combined phone/tablet interface
routes, with 34 required captures. Previously passed stream ordering, activity
interfaces and unrelated reading behavior are not selected. The same source
build covers reading plugins, catalog filters/details and bulk repository actions.

Local validation: the exact workflow shell selected precisely those 13 cases
using a recording xcodebuild stub. The new loopback repository served both owned
scripts and the intentional 404. Python compilation and supported formatter/lint
checks passed. These checks do not execute Swift or approve native interfaces.
Windows has no Apple SDK or Linux packaging host; native SDK validation remains
in Apple CI. No TypeScript or Rust implementation changed.

This is part of the active complete Desktop port, with one consolidated final
IPA still required. No IPA is produced by these validation runs.
