# Reading source and reader interface follow-up

The Desktop reference remains 0.9.132 Beta. This increment does not establish full
Desktop parity or produce an IPA.

Discovery and related book grids now pass their reading plugin manager explicitly
to each detail destination. The main Books grid already supplied that environment;
the other grids could reach the detail screen without a source resolver. The manual
HTML source editor puts validation errors before its fields, scrolls to the error,
and offers a keyboard Done action. Required configuration validation is unchanged.

Original run 40040069084 ended after its 40-minute UI step limit. Original logs and
xcresults agree on ten completed executions: eight passed and two failed. Another
seed has a passing result tree but no completed test log; it is retained as evidence
without approval. The collector now requires both records for every approved pass.

The iPhone cover failure waited for a lazy paragraph below the cover without
scrolling. The reader test now first checks the actual viewport, then reveals and
checks the original paragraph. The focus test activates the visible SwiftUI Menu
and requires its real settings sheet instead of treating the outer AX wrapper's
hittability as proof. Existing focus behavior and timing models are unchanged.

The next UI-only selection has ten fresh guests and ten routes, twenty executions
and fifty-four captures. Eight routes previously failed; iPad search remains an
affected route unexecuted after the timeout. A new focused iPhone landscape route
must scroll an unselected voice into the unobstructed list and actually select it.
It does not replay the previously approved complete phone voice journey. Full-screen
captures replace app-cropped screenshots for the reader's rotated states. The UI
step allows ninety minutes within the existing 120-minute job limit.

The fifty-one approved native reader/source models, public metadata contract, five
Rust font contracts and unrelated approved UI routes remain retained. Python/shell
selection preflight and scoped repository checks are preparation evidence. Actual
Apple execution and visual review of the selected changed routes are still required.
