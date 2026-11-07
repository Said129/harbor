import Foundation
import Network

/// Finds Chromecasts with Bonjour, as Desktop's `discover_chromecasts` does (`cast.rs`: `_googlecast._tcp`, 5 seconds).
/// The name is the TXT `fn` (or `n`) and the model is `md`, as `parse_friendly_name` and `parse_model` read them. The address
/// and port come from the resolved connection. Each service is resolved to IPv4 when it has one.
enum CastChromecastDiscovery {
    /// Must also appear in Info.plist `NSBonjourServices` as `_googlecast._tcp`. Unverified on hardware.
    static let serviceType = "_googlecast._tcp"
    static let browseTimeout: TimeInterval = 5

    static func discover() async -> [CastTarget] {
        await withCheckedContinuation { (continuation: CheckedContinuation<[CastTarget], Never>) in
            let browse = CastChromecastBrowse(serviceType: serviceType, timeout: browseTimeout) { targets in
                continuation.resume(returning: targets)
            }
            browse.start()
        }
    }

    static func target(host: String, port: UInt16, txt: [String: String]) -> CastTarget {
        CastTarget(
            id: "cc-\(host)-\(port)",
            kind: .chromecast,
            name: txt["fn"] ?? txt["n"] ?? "Chromecast",
            model: txt["md"],
            host: host,
            endpoint: "",
            port: port
        )
    }
}

/// One browse. All state is touched only on `queue`, which is why the class is marked unchecked.
private final class CastChromecastBrowse: @unchecked Sendable {
    private let serviceType: String
    private let timeout: TimeInterval
    private let finish: @Sendable ([CastTarget]) -> Void
    private let queue = DispatchQueue(label: "site.harbor.cast.chromecast.discovery")
    private var browser: NWBrowser?
    private var connections: [NWConnection] = []
    private var seen: Set<String> = []
    private var found: [String: CastTarget] = [:]
    private var finished = false

    init(serviceType: String, timeout: TimeInterval, finish: @escaping @Sendable ([CastTarget]) -> Void) {
        self.serviceType = serviceType
        self.timeout = timeout
        self.finish = finish
    }

    func start() {
        queue.async {
            let browser = NWBrowser(for: .bonjourWithTXTRecord(type: self.serviceType, domain: nil), using: .tcp)
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                self?.resolve(results)
            }
            browser.start(queue: self.queue)
            self.browser = browser
            self.queue.asyncAfter(deadline: .now() + self.timeout) { self.finishOnce() }
        }
    }

    /// Opens a connection to each new service only to learn the address it resolved to. The TXT record comes from the browse result.
    private func resolve(_ results: Set<NWBrowser.Result>) {
        guard !finished else { return }
        for result in results {
            let key = "\(result.endpoint)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            let txt = CastChromecastBrowse.txt(result.metadata)
            let connection = NWConnection(to: result.endpoint, using: .tcp)
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if let remote = connection.currentPath?.remoteEndpoint, case let .hostPort(host, port) = remote, let ip = CastChromecastBrowse.ipv4(host) {
                        self?.record(CastChromecastDiscovery.target(host: ip, port: port.rawValue, txt: txt))
                    }
                    connection.cancel()
                case .failed, .cancelled:
                    connection.cancel()
                default:
                    break
                }
            }
            connections.append(connection)
            connection.start(queue: queue)
        }
    }

    private func record(_ target: CastTarget) {
        guard !finished else { return }
        found[target.id] = target
    }

    private func finishOnce() {
        guard !finished else { return }
        finished = true
        browser?.cancel()
        connections.forEach { $0.cancel() }
        finish(found.values.sorted { $0.host < $1.host })
    }

    private static func txt(_ metadata: NWBrowser.Result.Metadata) -> [String: String] {
        if case let .bonjour(record) = metadata {
            return record.dictionary
        }
        return [:]
    }

    private static func ipv4(_ host: NWEndpoint.Host) -> String? {
        if case let .ipv4(address) = host { return "\(address)" }
        return nil
    }
}
