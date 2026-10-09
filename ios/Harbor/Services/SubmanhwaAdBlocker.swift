import Foundation
@preconcurrency import WebKit

/// Rules belong only to the embedded site browser. WebKit filters requests and
/// hides known ad containers without reading credentials or changing cookies.
@MainActor
enum SubmanhwaAdBlocker {
    private static var compiled: WKContentRuleList?
    // The first three are present in the site's public page, including its
    // click-triggered popunder. Other entries are dedicated advertising hosts.
    private static let advertisingDomains = [
        "jads.co", "juicyads.com", "massive-hall.com", "doubleclick.net",
        "googlesyndication.com", "adsterra.com", "exoclick.com", "exosrv.com",
        "popads.net", "popcash.net"
    ]

    static func contentRules() async throws -> WKContentRuleList {
        if let compiled { return compiled }
        var rules: [[String: Any]] = advertisingDomains.map { domain in
            ["trigger": ["url-filter": "^https?://([a-z0-9-]+\\.)*" + NSRegularExpression.escapedPattern(for: domain) + "([:/]|$)"],
             "action": ["type": "block"]]
        }
        let cosmeticTrigger: [String: Any] = ["url-filter": ".*", "if-domain": ["*submanhwa.com"]]
        rules.append([
            "trigger": cosmeticTrigger,
            "action": ["type": "css-display-none", "selector": ".home-ad, .home-ad-label, .ads-large, .ads-sqre1, .ads-sqre2, ins.adsbygoogle, iframe[src*='juicyads.com'], iframe[src*='jads.co']"]
        ])
        let data = try JSONSerialization.data(withJSONObject: rules, options: [.sortedKeys])
        guard let encoded = String(data: data, encoding: .utf8) else { throw HarborError(code: "content-blocker-rules") }
        let identifier = "harbor-submanhwa-ads-" + String(EBookShelf.hash(encoded).prefix(16))
        let list: WKContentRuleList = try await withCheckedThrowingContinuation { continuation in
            WKContentRuleListStore.default().compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: encoded) { list, error in
                if let error { continuation.resume(throwing: error) }
                else if let list { continuation.resume(returning: list) }
                else { continuation.resume(throwing: HarborError(code: "content-blocker-rules")) }
            }
        }
        compiled = list
        return list
    }

    static func blocks(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        return advertisingDomains.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    static func allowsNewWindow(_ url: URL?, navigation: WKNavigationType) -> Bool {
        guard let url, ["https", "http"].contains(url.scheme?.lowercased() ?? ""), !blocks(url), let host = url.host?.lowercased() else { return false }
        let site = host == "submanhwa.com" || host.hasSuffix(".submanhwa.com")
        // Keep same-site login/reading/gacha windows in this browser, and retain
        // explicit external links. Advertising scripts cannot replace the page
        // with an unsolicited external window, even on a reader tap.
        return site || navigation == .linkActivated
    }
}
