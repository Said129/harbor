import Foundation

/// Desktop skips an invalid section and continues applying independent sections.
/// Authentication, cancellation and a retired account still stop the whole pass.
@MainActor enum HarborLayoutSyncBatch {
    struct Step {
        let run: @MainActor () async throws -> Void
        init(_ run: @escaping @MainActor () async throws -> Void) { self.run = run }
    }
    static func run(_ steps: [Step], check: @MainActor () throws -> Void) async throws {
        var firstFailure: Error?
        for step in steps {
            try Task.checkCancellation(); try check()
            do { try await step.run() }
            catch {
                try Task.checkCancellation(); try check()
                if stopsPass(error) { throw error }
                if firstFailure == nil { firstFailure = error }
            }
            try Task.checkCancellation(); try check()
        }
        if let firstFailure { throw firstFailure }
    }
    private static func stopsPass(_ error: Error) -> Bool {
        if error is CancellationError || error is URLError { return true }
        guard let failure = error as? HarborError else { return false }
        return ["account-changed", "profile-auth-response", "invalid-account-request", "network", "http-401", "http-403", "http-429"].contains(failure.code)
    }
}
