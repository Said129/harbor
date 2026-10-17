import SwiftUI

struct SystemStorageView: View {
    private let maintenance = AppStorageMaintenance()
    @State private var report: AppStorageReport?
    @State private var imageBytes: Int64 = 0
    @State private var loading = false
    @State private var clearing = false
    @State private var refreshRevision = 0
    @State private var message: String?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HarborPageHeading(title: DesktopInterfaceText.value("Storage overview"))
                Text(DesktopInterfaceText.value("Documents, saved app data and caches on this device. Sizes exclude the app bundle and system Keychain."))
                    .font(HarborTheme.font(14)).foregroundStyle(.secondary)
                if loading && report == nil { ProgressView().frame(maxWidth: .infinity).padding() }
                if let report {
                    HarborSettingsSection("Storage overview") {
                        metric("Documents", bytes: report.documents)
                        metric("Saved app data", bytes: report.library)
                        metric("Caches", bytes: report.caches)
                        metric("Temporary files", bytes: report.temporary)
                        metric("Local app files", bytes: report.files)
                        if let available = report.available { metric("Available on device", bytes: available) }
                    }
                }
                HarborSettingsSection("Clear caches") {
                    metric("Downloaded image cache", bytes: imageBytes)
                    Button {
                        clearing = true; error = nil; message = nil
                        Task {
                            await ArtworkStore.shared.clearCache()
                            imageBytes = await ArtworkStore.shared.cachedBytes()
                            clearing = false; message = "Image cache cleared."
                            refreshRevision &+= 1
                        }
                    } label: {
                        HStack {
                            Text(DesktopInterfaceText.value("Clear image cache"))
                            Spacer()
                            if clearing { ProgressView() }
                        }.frame(minHeight: 44)
                    }.buttonStyle(HarborAccountButtonStyle()).disabled(clearing).accessibilityIdentifier("storage-clear-images")
                    AppHintView(hint: .imageCache, text: "Thumbnails download again when needed. Books, downloads, accounts and watch progress are kept.")
                }
                if let message { Text(DesktopInterfaceText.value(message)).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("storage-feedback") }
                if let error { Text(DesktopInterfaceText.value(error)).font(.caption).foregroundStyle(.orange) }
                Button(DesktopInterfaceText.value("Refresh")) { refreshRevision &+= 1 }
                    .buttonStyle(HarborAccountButtonStyle()).disabled(loading || clearing).accessibilityIdentifier("storage-refresh")
            }.padding(20)
        }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink)
            .navigationTitle(DesktopInterfaceText.value("Storage overview"))
            .accessibilityIdentifier("system-storage").task(id: refreshRevision) { await refresh(revision: refreshRevision) }
    }

    private func refresh(revision: Int) async {
        loading = true; error = nil
        defer { if revision == refreshRevision { loading = false } }
        do {
            let result = try await maintenance.measure()
            let bytes = await ArtworkStore.shared.cachedBytes()
            guard !Task.isCancelled, revision == refreshRevision else { return }
            report = result; imageBytes = bytes
        } catch is CancellationError { return }
        catch { if revision == refreshRevision { error = "Could not measure storage. Try again." } }
    }

    private func metric(_ title: String, bytes: Int64) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(DesktopInterfaceText.value(title))
            Spacer(minLength: 8)
            Text(ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)).foregroundStyle(.secondary).monospacedDigit()
        }.font(HarborTheme.font(14)).frame(minHeight: 36)
    }
}
