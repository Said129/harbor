import Foundation
import Observation

@MainActor @Observable final class TraktAccountModel {
    let store: TraktAccountStore
    private let client: TraktClient
    private let active: TraktClient.Active
    private let sleep: TraktClient.Sleep
    private let now: @Sendable () -> Date
    private var operation = UUID()
    private(set) var pin: TraktPin?
    private(set) var busy = false
    private(set) var error: String?
    private(set) var expiresAt: Date?
    init(store: TraktAccountStore, client: TraktClient = .shared, active: @escaping TraktClient.Active,
         sleep: @escaping TraktClient.Sleep = { try await Task.sleep(for: .seconds($0)) }, now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store; self.client = client; self.active = active; self.sleep = sleep; self.now = now
    }
    func load() {
        guard active() else { return }
        do { try store.load(); error = nil } catch { self.error = "Could not read the account on this device." }
    }
    func cancel() { operation = UUID(); pin = nil; expiresAt = nil; busy = false }
    private func current(_ ticket: UUID) -> Bool { operation == ticket && active() && !Task.isCancelled }
    func begin() async {
        cancel(); error = nil
        guard store.ready, active() else { return }
        let ticket = operation, identity = store.identity
        let lease: TraktClient.Lease = { [weak self] in await self?.current(ticket) ?? false }
        busy = true
        defer { if operation == ticket { busy = false; pin = nil; expiresAt = nil } }
        do {
            let issued = try TraktPin(try await client.reply(.deviceCode, current: lease).value())
            guard current(ticket), store.identity == identity else { return }
            let deadline = now().addingTimeInterval(issued.expiresIn)
            pin = issued; expiresAt = deadline; var interval = issued.interval
            while current(ticket), store.identity == identity, now() < deadline {
                let reply = try await client.reply(.poll(issued.deviceCode), current: lease)
                guard current(ticket), store.identity == identity else { return }
                switch reply.status {
                case 200:
                    var session = try TraktSession(reply.value())
                    do {
                        let user = try await client.reply(.me, token: session.accessToken, current: lease).value()
                        session.username = user["username"].string
                    } catch is CancellationError { throw CancellationError() }
                    catch { /* A granted token remains useful when the optional public name is unavailable. */ }
                    guard current(ticket), store.identity == identity else { return }
                    try store.set(session); return
                case 400: break
                case 429: interval += 5
                case 410: error = "Code expired. Try again."; return
                case 418: error = "Authorization was denied. Try again."; return
                default: throw TraktAPIError(status: reply.status)
                }
                try await sleep(min(interval, max(0, deadline.timeIntervalSince(now()))))
            }
            if current(ticket), store.identity == identity { error = "Code expired. Try again." }
        } catch is CancellationError { }
        catch { if current(ticket) { self.error = "Could not connect to Trakt. Try again." } }
    }
    func disconnect() {
        cancel(); guard active() else { return }
        do { try store.set(nil); error = nil } catch { self.error = "Could not save the account on this device." }
    }
}
