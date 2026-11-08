import SwiftUI

/// Desktop's channel card line under the name: the programme on air, then "Next:" with the one after it.
/// Shows nothing when no programme is on air. The line is re-read every 30 seconds, as Desktop's `useNowTick`.
struct LiveTVNowNextLine: View {
    let programs: [LiveProgram]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let pair = LiveTVGuideLookup.nowNext(programs, at: context.date)
            if let current = pair.current {
                VStack(alignment: .leading, spacing: 2) {
                    Text(current.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if let next = pair.next {
                        Text(DesktopInterfaceText.value("Next:") + " " + next.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
    }
}
