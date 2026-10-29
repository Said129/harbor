import Combine
import Foundation
import WebKit

@MainActor private final class SpooktoberWorldScheme: NSObject, WKURLSchemeHandler {
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        let id = ObjectIdentifier(task as AnyObject)
        tasks[id] = Task { [weak self] in
            do {
                guard let url = task.request.url, let path = SpooktoberWorldResources.path(url) else { throw HarborError(code: "spooktober-resource") }
                let resource = try await SpooktoberWorldResources.shared.resource(path)
                try Task.checkCancellation(); guard self?.tasks[id] != nil else { return }
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
                    "Content-Type": resource.mime, "Content-Length": String(resource.data.count), "Access-Control-Allow-Origin": "*"
                ])!
                task.didReceive(response); task.didReceive(resource.data); task.didFinish()
            } catch is CancellationError { }
            catch { if self?.tasks[id] != nil { task.didFailWithError(error) } }
            self?.tasks[id] = nil
        }
    }
    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {
        let id = ObjectIdentifier(task as AnyObject); tasks.removeValue(forKey: id)?.cancel()
    }
}
@MainActor private final class SpooktoberWorldMessages: NSObject, WKScriptMessageHandler {
    weak var controller: SpooktoberWorldController?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) { controller?.receive(message) }
}

/// Owns one original seasonal world. No account tokens, user files, or arbitrary
/// native commands are exposed to its document or embedded video frames.
@MainActor final class SpooktoberWorldController: NSObject, ObservableObject, WKNavigationDelegate {
    let store: SpooktoberWorldStore
    private let active: @MainActor () -> Bool
    private let intent: @MainActor (SpooktoberWorldIntent) -> Void
    private(set) var appearance: SpooktoberWorldAppearance
    private(set) var musicState: SpooktoberWorldMusicState = .idle
    private var visible = true
    private(set) var webView: WKWebView?
    @Published private(set) var ready = false
    @Published private(set) var failed = false
    @Published private(set) var storageError = false
    private(set) var diagnostic: String?
    init(store: SpooktoberWorldStore, appearance: SpooktoberWorldAppearance? = nil, active: @escaping @MainActor () -> Bool, intent: @escaping @MainActor (SpooktoberWorldIntent) -> Void) {
        self.store = store; self.appearance = appearance ?? .current(); self.active = active; self.intent = intent; super.init()
    }
    func start() {
        guard active(), store.ready else { failed = true; return }
        dispose()
        let handler = SpooktoberWorldMessages(); handler.controller = self
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(SpooktoberWorldScheme(), forURLScheme: SpooktoberWorldResources.scheme)
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.userContentController.add(handler, name: "spooktober")
        configuration.userContentController.addUserScript(WKUserScript(source: storageScript(), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.isOpaque = false; web.backgroundColor = .clear; web.scrollView.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.accessibilityIdentifier = "spooktober-world-web"
        web.navigationDelegate = self; webView = web; ready = false; failed = false; storageError = false; visible = true
        web.load(URLRequest(url: SpooktoberWorldResources.entry))
    }
    private func storageScript() -> String {
        let encoded = String(decoding: (try? JSONEncoder().encode(store.values)) ?? Data("{}".utf8), as: UTF8.self)
        let keys = String(decoding: (try? JSONEncoder().encode(SpooktoberWorldStore.keys.sorted())) ?? Data("[]".utf8), as: UTF8.self)
        let appearance = String(decoding: (try? JSONEncoder().encode(appearance)) ?? Data("{}".utf8), as: UTF8.self)
        let music = String(decoding: (try? JSONEncoder().encode(musicState)) ?? Data("{}".utf8), as: UTF8.self)
        return """
        (()=>{window.__harborSpookAppearance=\(appearance);window.__harborSpookMusicState=\(music);let values=\(encoded);const allowed=new Set(\(keys));
        const post=(key,value)=>window.webkit.messageHandlers.spooktober.postMessage(JSON.stringify({kind:"storage",key,value}));
        const storage={get length(){return Object.keys(values).length},key:index=>Object.keys(values)[index]??null,
          getItem:key=>values[String(key)]??null,
          setItem(key,value){key=String(key);if(!allowed.has(key))return;value=String(value);if(value.length>262144)return;values[key]=value;post(key,value)},
          removeItem(key){key=String(key);if(!allowed.has(key))return;delete values[key];post(key,null)},
          clear(){for(const key of Object.keys(values)){delete values[key];post(key,null)}}};
        Object.defineProperty(window,"localStorage",{configurable:true,value:storage});
        window.__harborSpookRestoreStorage=next=>{values=next};
        })();
        """
    }
    fileprivate func receive(_ message: WKScriptMessage) {
        guard active(), visible, message.webView === webView, message.frameInfo.isMainFrame,
              message.frameInfo.request.url?.scheme == SpooktoberWorldResources.scheme,
              message.frameInfo.request.url?.host == "world",
              let raw = message.body as? String, raw.utf8.count <= 512 * 1_024,
              let data = raw.data(using: .utf8), let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { return }
        switch value["kind"].string {
        case "ready": ready = true; failed = false
        case "failed": failed = true; diagnostic = value["message"].string
        case "intent":
            guard let request = SpooktoberWorldIntent.parse(value["message"]) else { return }
            if case .ready = request { return }; intent(request)
        case "storage":
            guard let key = value["key"].string else { return }
            do { try store.set(key, value: value["value"].string); storageError = false }
            catch {
                storageError = true
                let encoded = String(decoding: (try? JSONEncoder().encode(store.values)) ?? Data("{}".utf8), as: UTF8.self)
                webView?.evaluateJavaScript("window.__harborSpookRestoreStorage?.(\(encoded))")
            }
        default: break
        }
    }
    func setVisible(_ value: Bool) {
        visible = value
        let enabled = value && active()
        if enabled { applyAppearance(); applyMusicState() }
        webView?.evaluateJavaScript("window.__harborSpookWorld?.setActive(\(enabled ? "true" : "false"))")
    }
    func updateAppearance(_ value: SpooktoberWorldAppearance) {
        guard active(), appearance != value else { return }
        appearance = value
        if visible { applyAppearance() }
    }
    private func applyAppearance() {
        let encoded = String(decoding: (try? JSONEncoder().encode(appearance)) ?? Data("{}".utf8), as: UTF8.self)
        webView?.evaluateJavaScript("window.__harborSpookAppearance=\(encoded);window.__harborSpookWorld?.setAppearance(window.__harborSpookAppearance)")
    }
    func updateMusicState(_ value: SpooktoberWorldMusicState) {
        guard active(), musicState != value else { return }
        musicState = value
        if visible { applyMusicState() }
    }
    private func applyMusicState() {
        let encoded = String(decoding: (try? JSONEncoder().encode(musicState)) ?? Data("{}".utf8), as: UTF8.self)
        webView?.evaluateJavaScript("window.__harborSpookMusicState=\(encoded);window.__harborSpookWorld?.setMusicState(window.__harborSpookMusicState)")
    }
    func back() async -> Bool {
        guard active(), visible, let webView else { return false }
        if webView.canGoBack { webView.goBack(); return true }
        return (try? await webView.evaluateJavaScript("window.__harborSpookWorld?.back() ?? false")) as? Bool ?? false
    }
    func dispose() {
        webView?.evaluateJavaScript("window.__harborSpookWorld?.dispose()")
        webView?.stopLoading(); webView?.navigationDelegate = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "spooktober")
        webView = nil; ready = false
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard active(), let url = action.request.url else { return .cancel }
        if action.targetFrame?.isMainFrame != false {
            if SpooktoberWorldResources.path(url) != nil { return .allow }
            if let external = SpooktoberWorldIntent.externalURL(url.absoluteString), action.navigationType == .linkActivated { intent(.external(external)) }
            return .cancel
        }
        return ["www.youtube.com", "www.youtube-nocookie.com"].contains(url.host ?? "") && url.scheme == "https" ? .allow : .cancel
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { if self.webView === webView { failed = true } }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { if self.webView === webView { failed = true } }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { if self.webView === webView { ready = false; failed = true } }
}
