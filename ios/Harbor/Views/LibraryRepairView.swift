import SwiftUI

/// Desktop's "Repair library" row (`views/settings/advanced-panel/library-repair-rows.tsx`), as a preview: it shows the
/// records the repair would rewrite from the synced library. Writing waits for a LibraryModel method (see the port notes).
struct LibraryRepairView: View {
    let app: AppModel

    private var plan: LibraryRepairPlan { LibraryRepair.plan(app.library.items.map(\.raw)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                HarborSettingsSection(DesktopInterfaceText.value("Repair library")) {
                    content(plan)
                }
            }.padding(20)
        }.background(HarborTheme.background).navigationTitle(DesktopInterfaceText.value("Repair library"))
            .navigationBarTitleDisplayMode(.inline).tint(HarborTheme.accent)
            .accessibilityIdentifier("library-repair-scroll")
    }

    @ViewBuilder
    private func content(_ plan: LibraryRepairPlan) -> some View {
        if !app.library.hasCloudSession {
            Text(DesktopInterfaceText.value("Sign in to Stremio first. The repair scans only the active profile's library."))
                .font(HarborTheme.font(13)).foregroundStyle(.secondary)
        } else {
            Text(DesktopInterfaceText.value("Rewrites every library item to match Stremio's exact schema. Run once if your Stremio app started crashing after Harbor synced playback."))
                .font(HarborTheme.font(13)).foregroundStyle(.secondary)
            Text(statusLine(plan)).font(HarborTheme.font(14, weight: .semibold))
            ForEach(Array(plan.repairs.prefix(40).enumerated()), id: \.offset) { entry in
                Text(entry.element["name"].string ?? entry.element["_id"].string ?? "").font(HarborTheme.font(13))
            }
        }
    }

    /// Desktop's "normalizing" status: how many items would be rewritten. Nothing is written from this screen.
    private func statusLine(_ plan: LibraryRepairPlan) -> String {
        if plan.total == 0 { return DesktopInterfaceText.value("Library is empty. Nothing to repair.") }
        return DesktopInterfaceText.value("{n} items need repair.", variables: ["n": String(plan.needsRepair)])
    }
}
