import UIKit
import WebKit

/// Keeps website dialogs attached to their browser and completes them on close.
@MainActor
final class WebPageController: UIViewController, WKUIDelegate {
    let webView: WKWebView
    var openWindow: ((WKWebView, WKNavigationAction) -> Void)?
    private var siteDialog: UIAlertController?
    private var completeDialog: (() -> Void)?

    init(webView: WKWebView) {
        self.webView = webView
        super.init(nibName: nil, bundle: nil)
        webView.uiDelegate = self
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() { view = webView }

    func cancelSiteDialog() {
        let completion = completeDialog
        completeDialog = nil
        let dialog = siteDialog
        siteDialog = nil
        dialog?.dismiss(animated: false)
        completion?()
    }
    func close() {
        cancelSiteDialog()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        openWindow = nil
    }
    private func finish(_ action: () -> Void) {
        guard completeDialog != nil else { return }
        completeDialog = nil
        siteDialog = nil
        action()
    }
    private func show(_ dialog: UIAlertController, cancelled: @escaping () -> Void) {
        guard viewIfLoaded?.window != nil, !isBeingDismissed, !isMovingFromParent, presentedViewController == nil, completeDialog == nil else {
            cancelled()
            return
        }
        siteDialog = dialog
        completeDialog = cancelled
        present(dialog, animated: true)
    }
    private func origin(_ frame: WKFrameInfo) -> String {
        frame.request.url?.host ?? webView.url?.host ?? "Página web"
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @Sendable () -> Void) {
        let dialog = UIAlertController(title: origin(frame), message: message, preferredStyle: .alert)
        dialog.addAction(UIAlertAction(title: "Aceptar", style: .default) { [weak self] _ in self?.finish(completionHandler) })
        show(dialog, cancelled: completionHandler)
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (Bool) -> Void) {
        let dialog = UIAlertController(title: origin(frame), message: message, preferredStyle: .alert)
        dialog.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { [weak self] _ in self?.finish { completionHandler(false) } })
        dialog.addAction(UIAlertAction(title: "Aceptar", style: .default) { [weak self] _ in self?.finish { completionHandler(true) } })
        show(dialog, cancelled: { completionHandler(false) })
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (String?) -> Void) {
        let dialog = UIAlertController(title: origin(frame), message: prompt, preferredStyle: .alert)
        dialog.addTextField { $0.text = defaultText }
        dialog.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { [weak self] _ in self?.finish { completionHandler(nil) } })
        dialog.addAction(UIAlertAction(title: "Aceptar", style: .default) { [weak self, weak dialog] _ in self?.finish { completionHandler(dialog?.textFields?.first?.text) } })
        show(dialog, cancelled: { completionHandler(nil) })
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        openWindow?(webView, action)
        return nil
    }
}
