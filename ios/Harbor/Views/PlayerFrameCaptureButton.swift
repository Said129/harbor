import SwiftUI
import UniformTypeIdentifiers

struct PlayerFrameCaptureButton: View {
    let state: PlayerState
    @State private var operation: Task<Void, Never>?
    @State private var frame: PlayerFrameDocument?
    @State private var exporting = false
    @State private var captureFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { capture() } label: {
                Label(DesktopInterfaceText.value("Screenshot"), systemImage: "camera").frame(minHeight: 44)
            }
            .disabled(operation != nil || exporting || state.controller?.canCaptureFrame != true)
            .accessibilityIdentifier("player-capture-frame")
            if captureFailed {
                Text(DesktopInterfaceText.value("Frame grab failed")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .fileExporter(isPresented: $exporting, document: frame, contentType: .png,
                      defaultFilename: "Harbor - " + Date().ISO8601Format().replacingOccurrences(of: ":", with: "-") + ".png") { result in
            if case .failure(let error) = result, (error as? CocoaError)?.code != .userCancelled { captureFailed = true }
            frame = nil
        }
        .onDisappear { operation?.cancel() }
    }

    private func capture() {
        guard operation == nil, let controller = state.controller else { return }
        captureFailed = false
        frame = nil
        operation = Task {
            defer { operation = nil }
            do {
                let png = try await controller.captureFrame()
                try Task.checkCancellation()
                frame = PlayerFrameDocument(data: png)
                exporting = true
            } catch {
                if !Task.isCancelled { captureFailed = true }
            }
        }
    }
}

private struct PlayerFrameDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.png]
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
