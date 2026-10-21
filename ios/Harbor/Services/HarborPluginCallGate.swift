import Foundation

/// The reference limits plugin operations to eight, independently of HTTP bridge concurrency.
@MainActor final class HarborPluginCallGate {
    static let shared = HarborPluginCallGate()
    private let limit: Int
    private var active = 0
    private var waiting: [(UUID, CheckedContinuation<Void, Error>)] = []
    init(limit: Int = 8) { self.limit = max(1, limit) }

    func acquire() async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else if active < limit { active += 1; continuation.resume() }
                else { waiting.append((id, continuation)) }
            }
        } onCancel: { Task { @MainActor in self.cancel(id) } }
    }
    func release() {
        guard active > 0 else { return }
        if waiting.isEmpty { active -= 1 }
        else { waiting.removeFirst().1.resume() }
    }
    private func cancel(_ id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.0 == id }) else { return }
        waiting.remove(at: index).1.resume(throwing: CancellationError())
    }
}
