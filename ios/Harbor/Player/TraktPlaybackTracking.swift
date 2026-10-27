import Network
import SwiftUI

@MainActor final class TraktPlaybackDelivery {
    static let shared = TraktPlaybackDelivery()
    private var previous: Task<Void, Never>?
    func enqueue(_ operation: @escaping @MainActor @Sendable () async -> Void) -> Task<Void, Never> {
        let before = previous, task = Task { await before?.value; await operation() }
        previous = task; return task
    }
}

@MainActor final class TraktPlaybackTracker {
    private let reporter: TraktWatchReporter
    private let delivery: TraktPlaybackDelivery
    private var policy = TraktPlaybackPolicy()
    private var previous: Task<Void, Never>?
    private var closed = false
    init(reporter: TraktWatchReporter, delivery: TraktPlaybackDelivery? = nil) {
        self.reporter = reporter; self.delivery = delivery ?? .shared
    }
    func sample(identity: TraktWatchIdentity, status: TraktPlaybackPolicy.Status, position: Double, duration: Double, now: TimeInterval = Date().timeIntervalSince1970, isClockTick: Bool = false) {
        guard !closed else { return }
        for event in policy.update(identity: identity, status: status, position: position, duration: duration, now: now, isClockTick: isClockTick) { enqueue(event) }
    }
    func finish(identity: TraktWatchIdentity? = nil, position: Double? = nil, duration: Double? = nil) {
        guard !closed else { return }; closed = true
        if let event = policy.finish(identity: identity, position: position, duration: duration) { enqueue(event) }
    }
    private func enqueue(_ delivery: TraktPlaybackPolicy.Delivery) {
        let reporter = reporter
        previous = self.delivery.enqueue { await reporter.send(delivery.event, identity: delivery.identity) }
    }
    func settled() async { await previous?.value }
}

struct TraktPlaybackTracking: ViewModifier {
    let state: PlayerState
    let session: PlaybackSession
    let media: Media?
    let library: LibraryModel?
    let resumePending: Bool
    @State private var tracker: TraktPlaybackTracker?
    private var account: TraktAccountStore? { library.map { .forOwner($0.personalOwner) } }
    private var identity: TraktWatchIdentity { .init(session: session, media: session.media ?? media) }
    private var taskID: String {
        [session.id.uuidString, library?.personalOwner ?? "", AppProfileContext.shared.activationID.uuidString,
         account?.identity.uuidString ?? "", String(resumePending)].joined(separator: "|")
    }
    private var status: TraktPlaybackPolicy.Status {
        if state.ended { return .ended }
        if !state.loaded || state.buffering || state.restarting || state.error != nil || resumePending { return .loading }
        return state.paused ? .paused : .playing
    }
    func body(content: Content) -> some View {
        content.task(id: taskID) {
            guard !resumePending, session.progressEnabled, let library, let account else { return }
            let context = AppProfileContext.shared, activation = context.activationID, generation = context.playback.generation
            let owner = library.personalOwner, accountIdentity = account.identity
            guard context.binding?.personalOwner == owner else { return }
            do { if !account.ready { try account.load() } } catch { Diagnostics.shared.recordFailure(error); return }
            // Loading a saved grant changes the observed identity and restarts
            // this task. Only that replacement task may send its first start.
            guard account.identity == accountIdentity, account.session != nil else { return }
            let reporter = TraktWatchReporter(account: account, queue: .forOwner(owner), active: { [weak library, weak context] in
                context?.activationID == activation && context?.playback.generation == generation && library?.personalOwner == owner
            })
            let tracker = TraktPlaybackTracker(reporter: reporter); self.tracker = tracker
            defer { tracker.finish(); if self.tracker === tracker { self.tracker = nil } }
            tracker.sample(identity: identity, status: status, position: state.position, duration: state.duration)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
                tracker.sample(identity: identity, status: status, position: state.position, duration: state.duration, isClockTick: true)
            }
        }.onChange(of: status) { _, _ in sample() }
            .onChange(of: state.duration) { _, _ in sample() }
            .onChange(of: identity) { _, _ in sample() }
            .onDisappear { tracker?.finish(identity: identity, position: state.position, duration: state.duration); tracker = nil }
    }
    private func sample() {
        guard !resumePending else { return }
        tracker?.sample(identity: identity, status: status, position: state.position, duration: state.duration)
    }
}

private final class TraktNetworkObservation: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    func events() -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            monitor.pathUpdateHandler = { path in if path.status == .satisfied { continuation.yield(()) } }
            continuation.onTermination = { [self] _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "harbor.trakt.online"))
        }
    }
}

struct TraktPendingRecovery: ViewModifier {
    let app: AppModel
    @Environment(\.scenePhase) private var scenePhase
    private var account: TraktAccountStore { .forOwner(app.personalOwner) }
    func body(content: Content) -> some View {
        content.background {
            if app.storageReady && scenePhase == .active, account.session != nil {
                Color.clear.frame(width: 0, height: 0).task(id: app.accountOperationScope + "|" + account.identity.uuidString) {
                    let owner = app.personalOwner, scope = app.accountOperationScope
                    let reporter = TraktWatchReporter(account: account, queue: .forOwner(owner), active: { [weak app] in
                        app?.storageReady == true && app?.personalOwner == owner && app?.accountOperationScope == scope
                    })
                    for await _ in TraktNetworkObservation().events() {
                        guard !Task.isCancelled else { return }; await reporter.recover()
                    }
                }
            }
        }.task(id: app.accountOperationScope + "|" + String(app.storageReady)) {
            guard app.storageReady else { return }
            do { if !account.ready { try account.load() } } catch { Diagnostics.shared.recordFailure(error) }
        }
    }
}
