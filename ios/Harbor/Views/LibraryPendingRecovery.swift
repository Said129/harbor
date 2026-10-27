import Network
import SwiftUI

private final class LibraryNetworkObservation: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    func events() -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            monitor.pathUpdateHandler = { path in if path.status == .satisfied { continuation.yield(()) } }
            continuation.onTermination = { [self] _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "harbor.library.online"))
        }
    }
}
struct LibraryPendingRecovery: ViewModifier {
    let app: AppModel
    @Environment(\.scenePhase) private var scenePhase
    func body(content: Content) -> some View {
        content.background {
            if app.storageReady && app.library.hasCloudSession && scenePhase == .active {
                Color.clear.frame(width: 0, height: 0)
                    .task(id: app.accountOperationScope) {
                        for await _ in LibraryNetworkObservation().events() {
                            guard !Task.isCancelled else { return }
                            await app.library.flushPendingWrites()
                        }
                    }
                    .task(id: app.accountOperationScope) {
                        while !Task.isCancelled {
                            await app.library.flushPendingWrites()
                            do { try await Task.sleep(for: .seconds(60)) } catch { return }
                        }
                    }
            }
        }
    }
}
