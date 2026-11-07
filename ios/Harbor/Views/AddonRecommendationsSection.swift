import SwiftUI

/// Desktop "Recommended for you" rail on the addon detail page. It is self-contained: give it the
/// app model and the addon being viewed. Pass `open` so configurable addons can open their own detail.
@MainActor
struct AddonRecommendationsSection: View {
    let app: AppModel
    let target: Addon
    var open: ((Addon) -> Void)? = nil
    @State private var catalog: [Addon] = []
    @State private var items: [Addon] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !items.isEmpty {
                Text(DesktopInterfaceText.value("Recommended for you")).font(.headline)
                ForEach(items) { addon in
                    AddonRecommendationRow(app: app, addon: addon, open: open)
                }
            }
        }
        .accessibilityIdentifier("addon-recommendations")
        .task(id: target.id) { await loadCatalog() }
        .onChange(of: app.addons.map { AddonRecommendations.key($0) }) { _, _ in recompute() }
    }

    private func loadCatalog() async {
        do {
            let result = try await AddonDirectory.shared.load()
            try Task.checkCancellation()
            catalog = result.addons
            recompute()
        } catch is CancellationError {
            return
        } catch {
            catalog = []
            items = []
        }
    }

    private func recompute() {
        let installedIDs = Set(app.addons.map { AddonRecommendations.key($0) })
        // Desktop also excludes the "More like this" rail here; iOS does not show that rail yet.
        items = AddonRecommendations.recommended(
            for: target,
            candidates: catalog + app.addons,
            installedIDs: installedIDs,
            exclude: []
        )
    }
}

@MainActor
private struct AddonRecommendationRow: View {
    let app: AppModel
    let addon: Addon
    let open: ((Addon) -> Void)?
    @State private var busy = false
    @State private var error: String?

    private var installed: Bool {
        let id = AddonRecommendations.key(addon)
        return app.addons.contains { AddonRecommendations.key($0) == id }
    }

    private var buttonTitle: String {
        if installed { return DesktopInterfaceText.value("Installed") }
        if busy { return DesktopInterfaceText.value("Installing") }
        return DesktopInterfaceText.value("Install")
    }

    private var unavailable: Bool {
        installed || busy || app.accountBusy || !app.storageReady || (addon.configurable && open == nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                AddonLogo(addon: addon, size: 40)
                Text(addon.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { install() } label: { Text(buttonTitle) }
                    .buttonStyle(HarborAccountButtonStyle(primary: true))
                    .disabled(unavailable)
                    .accessibilityIdentifier("addon-recommendation-install")
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
        }
    }

    private func install() {
        guard !busy, !installed else { return }
        if addon.configurable {
            open?(addon)
            return
        }
        let owner = app.accountOperationScope
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await app.install(addon.transportUrl, expectedManifestID: addon.manifest["id"].string)
            } catch {
                if owner == app.accountOperationScope { self.error = safeMessage(error) }
            }
        }
    }
}
