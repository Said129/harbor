import AuthenticationServices
import UIKit

/// The official Stremio browser login used by Desktop, presented by iOS.
/// No credentials or web content are read by the application.
@MainActor
final class StremioWebLogin: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var pending: CheckedContinuation<String, Error>?
    private var attempt: String?
    private var timeout: Task<Void, Never>?

    func start() async throws -> String {
        guard pending == nil else { throw HarborError(code: "account-busy") }
        let nonce = UUID().uuidString
        attempt = nonce
        let callback = "harbor-iphone://signin/\(nonce)"
        var components = URLComponents(string: "https://www.stremio.com/login")!
        components.queryItems = [URLQueryItem(name: "appName", value: "Harbor"), URLQueryItem(name: "appCallback", value: callback)]
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending = continuation
                let auth = ASWebAuthenticationSession(url: components.url!, callbackURLScheme: "harbor-iphone") { [weak self] url, error in
                    Task { @MainActor in
                        guard let self, self.attempt == nonce else { return }
                        guard error == nil, let url else { self.finish(.failure(HarborError(code: "account-cancelled"))); return }
                        guard url.scheme == "harbor-iphone", url.host == "signin", url.path == "/\(nonce)",
                              let values = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                              let key = values.first(where: { $0.name == "key" || $0.name == "authKey" })?.value,
                              !key.isEmpty else { self.finish(.failure(HarborError(code: "invalid-account-response"))); return }
                        self.finish(.success(key))
                    }
                }
                auth.presentationContextProvider = self
                session = auth
                if !auth.start() { finish(.failure(HarborError(code: "account-browser-unavailable"))) }
                else {
                    timeout = Task { [weak self] in
                        do { try await Task.sleep(for: .seconds(300)) } catch { return }
                        guard let self, self.attempt == nonce else { return }
                        self.finish(.failure(HarborError(code: "account-timeout")))
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.attempt == nonce else { return }
                self.finish(.failure(CancellationError()))
            }
        }
    }

    private func finish(_ result: Result<String, Error>) {
        let continuation = pending
        pending = nil
        attempt = nil
        timeout?.cancel(); timeout = nil
        session?.cancel()
        session = nil
        continuation?.resume(with: result)
    }

    func cancel() { finish(.failure(HarborError(code: "account-cancelled"))) }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
