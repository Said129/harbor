import SwiftUI
import WebKit

struct AddonConfigurationView: View {
    let name: String
    let url: URL
    let receive: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var loading = true
    @State private var error: String?
    var body: some View {
        VStack(spacing: 0) {
            if loading { ProgressView().padding(8) }
            if let error { Text(error).font(.caption).foregroundStyle(.orange).padding() }
            AddonConfigurationSurface(url: url, loading: $loading, error: $error) { candidate in
                receive(candidate)
                dismiss()
            }
        }.navigationTitle(name).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Abrir en Safari") { UIApplication.shared.open(url) } }
            }
    }
}

private struct AddonConfigurationSurface: UIViewControllerRepresentable {
    let url: URL
    @Binding var loading: Bool
    @Binding var error: String?
    let receive: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> WebPageController {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        let controller = WebPageController(webView: view)
        context.coordinator.controller = controller
        view.navigationDelegate = context.coordinator
        controller.openWindow = { [weak coordinator = context.coordinator] view, action in coordinator?.openWindow(view, action: action) }
        view.allowsBackForwardNavigationGestures = true
        view.load(URLRequest(url: url))
        return controller
    }
    func updateUIViewController(_ controller: WebPageController, context: Context) { context.coordinator.parent = self }
    static func dismantleUIViewController(_ controller: WebPageController, coordinator: Coordinator) { controller.close() }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: AddonConfigurationSurface
        weak var controller: WebPageController?
        private var received = false
        init(_ parent: AddonConfigurationSurface) { self.parent = parent }
        private func capture(_ url: URL) -> Bool {
            let scheme = url.scheme?.lowercased() ?? ""
            guard scheme == "stremio" || (["https", "http"].contains(scheme) && url.path.lowercased().hasSuffix("/manifest.json")) else { return false }
            guard !received else { return true }
            guard url.absoluteString.utf8.count <= 32_768 else { parent.error = "El enlace de configuración es demasiado largo."; return true }
            received = true
            parent.receive(url.absoluteString)
            return true
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = action.request.url else { return .cancel }
            if action.targetFrame?.isMainFrame != false, capture(url) { return .cancel }
            return ["http", "https", "about"].contains(url.scheme?.lowercased() ?? "") ? .allow : .cancel
        }
        func openWindow(_ webView: WKWebView, action: WKNavigationAction) {
            guard let url = action.request.url, !capture(url), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
            webView.load(action.request)
        }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { controller?.cancelSiteDialog(); parent.loading = true; parent.error = nil }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { parent.loading = false }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
        private func failed(_ error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            parent.loading = false
            parent.error = "No se pudo cargar la configuración. Puedes cerrar y volver a intentarlo o abrirla en Safari."
        }
    }
}
