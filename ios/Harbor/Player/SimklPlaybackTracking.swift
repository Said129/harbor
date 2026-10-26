import SwiftUI
import Network

@MainActor final class SimklPlaybackDelivery {
    static let shared = SimklPlaybackDelivery()
    private var previous: Task<Void, Never>?
    func enqueue(_ operation: @escaping @MainActor @Sendable () async -> Void) -> Task<Void, Never> {
        let before = previous, task = Task { await before?.value; await operation() }
        previous = task; return task
    }
}
@MainActor final class SimklPlaybackTracker {
    let identity: SimklWatchIdentity
    private let reporter: SimklWatchReporter
    private let delivery: SimklPlaybackDelivery
    private var policy = SimklPlaybackPolicy()
    private var previous: Task<Void, Never>?
    private var closed = false
    init(identity: SimklWatchIdentity, reporter: SimklWatchReporter, delivery: SimklPlaybackDelivery? = nil) {
        self.identity = identity; self.reporter = reporter; self.delivery = delivery ?? .shared
    }
    func sample(status: SimklPlaybackPolicy.Status, position: Double, duration: Double) {
        guard !closed else { return }
        if let event = policy.update(status: status, position: position, duration: duration) { enqueue(event) }
    }
    func finish(position: Double, duration: Double) {
        guard !closed else { return }; closed = true
        if let event = policy.finish(position: position, duration: duration) { enqueue(event) }
    }
    private func enqueue(_ event: SimklPlaybackPolicy.Event) {
        let reporter = reporter, identity = identity
        previous = delivery.enqueue { await reporter.send(event, identity: identity) }
    }
    func settled() async { await previous?.value }
}

struct SimklPlaybackTracking: ViewModifier {
    let state: PlayerState
    let session: PlaybackSession
    let media: Media?
    let library: LibraryModel?
    let resumePending: Bool
    var reporter: SimklWatchReporter? = nil
    @State private var tracker: SimklPlaybackTracker?
    @AppStorage("simklScrobbleEnabled") private var enabled = true
    private var status: SimklPlaybackPolicy.Status {
        if state.ended { return .ended }
        if !state.loaded || state.buffering || state.restarting || state.error != nil || resumePending { return .loading }
        return state.paused ? .paused : .playing
    }
    func body(content: Content) -> some View {
        content.task(id: enabled && !resumePending) {
            guard enabled, !resumePending, session.progressEnabled, let library else { return }
            let reporter: SimklWatchReporter
            if let provided = self.reporter { reporter = provided }
            else {
                let context = AppProfileContext.shared, activation = context.activationID, generation = context.playback.generation
                let owner = library.personalOwner, account = SimklAccountStore.forOwner(owner)
                guard context.binding?.personalOwner == owner else { return }
                do { if !account.ready { try account.load() } } catch { return }
                guard account.session != nil else { return }
                reporter = SimklWatchReporter(account: account, queue: .forOwner(owner), active: { [weak library, weak context] in
                    context?.activationID == activation && context?.playback.generation == generation && library?.personalOwner == owner
                        && (UserDefaults.standard.object(forKey: "simklScrobbleEnabled") == nil || UserDefaults.standard.bool(forKey: "simklScrobbleEnabled"))
                })
            }
            let tracker = SimklPlaybackTracker(identity: .init(session: session, media: session.media ?? media), reporter: reporter)
            self.tracker = tracker
            while !Task.isCancelled {
                if !resumePending { tracker.sample(status: status, position: state.position, duration: state.duration) }
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
            }
        }.onChange(of: status) { _, _ in if enabled && !resumePending { tracker?.sample(status: status, position: state.position, duration: state.duration) } }
            .onDisappear { if enabled { tracker?.finish(position: state.position, duration: state.duration) }; tracker = nil }
    }
}

private final class SimklNetworkObservation: @unchecked Sendable {
    let monitor = NWPathMonitor()
    func events() -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            monitor.pathUpdateHandler = { path in if path.status == .satisfied { continuation.yield(()) } }
            continuation.onTermination = { [self] _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "harbor.simkl.online"))
        }
    }
}
struct SimklPendingRecovery: ViewModifier {
    let app: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("simklScrobbleEnabled") private var enabled = true
    private var account: SimklAccountStore { .forOwner(app.personalOwner) }
    func body(content: Content) -> some View {
        content.background {
            if enabled && app.storageReady && scenePhase == .active, let token = account.session?.accessToken {
                Color.clear.frame(width: 0, height: 0).task(id: app.accountOperationScope + "|" + EBookShelf.hash(token)) {
                    let owner = app.personalOwner, scope = app.accountOperationScope
                    let reporter = SimklWatchReporter(account: account, queue: .forOwner(owner), active: { [weak app] in
                        app?.personalOwner == owner && app?.accountOperationScope == scope && app?.storageReady == true
                            && (UserDefaults.standard.object(forKey: "simklScrobbleEnabled") == nil || UserDefaults.standard.bool(forKey: "simklScrobbleEnabled"))
                    })
                    for await _ in SimklNetworkObservation().events() {
                        guard !Task.isCancelled else { return }; await reporter.recover()
                    }
                }
            }
        }.task(id: app.accountOperationScope + "|" + String(app.storageReady) + "|" + String(enabled)) {
            guard app.storageReady, enabled else { return }; do { if !account.ready { try account.load() } } catch { }
        }
    }
}
