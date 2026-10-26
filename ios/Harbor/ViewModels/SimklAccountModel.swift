import Foundation
import Observation

@MainActor @Observable final class SimklAccountModel {
    let store: SimklAccountStore
    private let client: SimklClient
    private let active: @MainActor () -> Bool
    private let sleep: SimklClient.Sleep
    private let now: @Sendable () -> Date
    private var operation = UUID()
    private(set) var pin: SimklPin?
    private(set) var busy = false
    private(set) var error: String?
    private(set) var expiresAt: Date?
    init(store: SimklAccountStore, client: SimklClient = .shared, active: @escaping @MainActor () -> Bool,
        sleep: @escaping SimklClient.Sleep = { try await Task.sleep(for: .seconds($0)) }, now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store; self.client = client; self.active = active; self.sleep = sleep; self.now = now
    }
    func load() {
        guard active() else { return }
        do { try store.load(); error = nil } catch { self.error = "Could not read the account on this device." }
    }
    func cancel() { operation = UUID(); pin = nil; expiresAt = nil; busy = false }
    func begin() async {
        cancel(); error = nil
        guard active(), store.ready else { return }
        let ticket = operation
        let current: SimklClient.Lease = { [weak self] in await self?.isCurrent(ticket) ?? false }
        busy = true
        defer { if operation == ticket { busy = false; pin = nil; expiresAt = nil } }
        do {
            let value = try await client.response(.pin, current: current)
            guard isCurrent(ticket) else { return }
            let issued = try SimklPin(value), deadline = now().addingTimeInterval(issued.expiresIn)
            pin = issued; expiresAt = deadline
            while isCurrent(ticket), now() < deadline {
                var response: JSONValue?
                do { response = try await client.response(.poll(issued.userCode), current: current) }
                catch is CancellationError { throw CancellationError() }
                catch let error as SimklAPIError where error.retryAt != nil { throw error }
                catch { /* A transient poll failure retries at the provider interval. */ }
                guard isCurrent(ticket) else { return }
                if response?["result"].string == "OK", let token = response?["access_token"].string, SimklEndpoint.validToken(token) {
                    var session = SimklSession(accessToken: token)
                    do {
                        let settings = try await client.response(.settings, token: token, current: current)
                        session.username = settings["user"]["name"].string
                    } catch is CancellationError { throw CancellationError() }
                    catch let error as SimklAPIError where error.status == 401 { throw error }
                    catch { /* The granted token remains usable if the optional name is unavailable. */ }
                    guard isCurrent(ticket) else { return }
                    try store.set(session); return
                }
                try await sleep(min(issued.pollInterval, max(0, deadline.timeIntervalSince(now()))))
            }
            if isCurrent(ticket) { error = "Code expired. Try again." }
        } catch is CancellationError { }
        catch let failure as SimklAPIError {
            if isCurrent(ticket) { error = failure.status == 401 ? "Authorization expired. Connect again." : failure.retryAt != nil ? "Simkl is temporarily limiting requests. Try again later." : "Could not connect to Simkl. Try again." }
        } catch { if isCurrent(ticket) { self.error = "Could not connect to Simkl. Try again." } }
    }
    func disconnect() {
        cancel(); guard active() else { return }
        do { try store.set(nil); error = nil } catch { self.error = "Could not save the account on this device." }
    }
    private func isCurrent(_ ticket: UUID) -> Bool { operation == ticket && active() && !Task.isCancelled }
}
