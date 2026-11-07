import Darwin
import Foundation
import Network

/// Finds Roku candidates on iOS, where SSDP multicast needs an entitlement Harbor does not have.
/// Two sources feed one ECP probe: a Bonjour browse for the service types in Info.plist, and a unicast
/// probe of the device's own /24 on port 8060. DLNA renderers are not discovered; they are added by description URL.
enum CastDiscovery {
    /// Bonjour types to browse. Each must also appear in Info.plist `NSBonjourServices`. Unverified on hardware.
    static let bonjourServiceTypes = ["_roku-rcp._tcp"]
    static let probeConcurrency = 24
    static let probeTimeout: TimeInterval = 1.5
    static let bonjourTimeout: TimeInterval = 4

    /// The 254 host addresses of the /24 that contains `localIPv4`, the device itself excluded.
    static func subnetHosts(localIPv4: String) -> [String] {
        let parts = localIPv4.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts.allSatisfy({ part in Int(part).map { (0...255).contains($0) } ?? false }) else { return [] }
        let prefix = parts[0...2].joined(separator: ".")
        return (1...254).map { "\(prefix).\($0)" }.filter { $0 != localIPv4 }
    }

    /// The Wi-Fi IPv4 address (`en0`), or nil when the device is not on Wi-Fi.
    static func localIPv4() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            let info = entry.pointee
            if String(cString: info.ifa_name) == "en0", let address = info.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET) {
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(address, socklen_t(address.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                    return String(cString: buffer)
                }
            }
            cursor = info.ifa_next
        }
        return nil
    }

    /// Roku devices that answer `query/device-info` on one of the hosts, probed with at most `probeConcurrency` at a time.
    static func probe(hosts: [String], transport: CastTransport) async -> [CastTarget] {
        var found: [CastTarget] = []
        for start in stride(from: 0, to: hosts.count, by: probeConcurrency) {
            let chunk = Array(hosts[start..<min(start + probeConcurrency, hosts.count)])
            let targets = await withTaskGroup(of: CastTarget?.self, returning: [CastTarget].self) { group in
                for host in chunk {
                    group.addTask { await probeRoku(host: host, transport: transport) }
                }
                var results: [CastTarget] = []
                for await target in group {
                    if let target { results.append(target) }
                }
                return results
            }
            found.append(contentsOf: targets)
        }
        return found.sorted { $0.host < $1.host }
    }

    /// A single ECP device-info probe. Only a `<device-info>` document counts, so other services on 8060 are ignored.
    static func probeRoku(host: String, transport: CastTransport) async -> CastTarget? {
        let base = CastRoku.ecpBase(forHost: host)
        guard let request = CastRoku.deviceInfoRequest(base: base, timeout: probeTimeout) else { return nil }
        guard let reply = try? await transport.send(request), reply.status == 200, reply.body.contains("<device-info") else { return nil }
        let info = CastRoku.parseDeviceInfo(reply.body)
        return CastTarget(id: "roku-" + host, kind: .roku, name: info.name, model: info.model, host: host, endpoint: base)
    }

    /// Everything reachable right now: Bonjour hosts first, then the local /24. Duplicates are removed.
    static func discoverRokus(transport: CastTransport) async -> [CastTarget] {
        let bonjour = await CastBonjour.hosts(serviceTypes: bonjourServiceTypes, timeout: bonjourTimeout)
        var hosts = bonjour
        if let local = localIPv4() {
            for host in subnetHosts(localIPv4: local) where !hosts.contains(host) {
                hosts.append(host)
            }
        }
        return await probe(hosts: hosts, transport: transport)
    }
}

/// Bonjour browse for the Roku types. Each result is resolved to an IPv4 address, and silent results are skipped.
enum CastBonjour {
    static func hosts(serviceTypes: [String], timeout: TimeInterval) async -> [String] {
        await withCheckedContinuation { (continuation: CheckedContinuation<[String], Never>) in
            let session = CastBonjourSession(serviceTypes: serviceTypes, timeout: timeout) { hosts in
                continuation.resume(returning: hosts)
            }
            session.start()
        }
    }
}

/// One browse. All state is touched only on `queue`, which is why the class is marked unchecked.
private final class CastBonjourSession: @unchecked Sendable {
    private let serviceTypes: [String]
    private let timeout: TimeInterval
    private let finish: @Sendable ([String]) -> Void
    private let queue = DispatchQueue(label: "site.harbor.cast.bonjour")
    private var browsers: [NWBrowser] = []
    private var connections: [NWConnection] = []
    private var resolved: Set<String> = []
    private var hosts: Set<String> = []
    private var finished = false

    init(serviceTypes: [String], timeout: TimeInterval, finish: @escaping @Sendable ([String]) -> Void) {
        self.serviceTypes = serviceTypes
        self.timeout = timeout
        self.finish = finish
    }

    func start() {
        queue.async {
            for type in self.serviceTypes {
                let browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: .tcp)
                browser.browseResultsChangedHandler = { [weak self] results, _ in
                    self?.resolve(results)
                }
                browser.start(queue: self.queue)
                self.browsers.append(browser)
            }
            self.queue.asyncAfter(deadline: .now() + self.timeout) { self.finishOnce() }
        }
    }

    private func resolve(_ results: Set<NWBrowser.Result>) {
        guard !finished else { return }
        for result in results {
            let key = "\(result.endpoint)"
            guard !resolved.contains(key) else { continue }
            resolved.insert(key)
            let connection = NWConnection(to: result.endpoint, using: .tcp)
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if let remote = connection.currentPath?.remoteEndpoint, case let .hostPort(host, _) = remote, let ip = Self.ipv4(host) {
                        self?.hosts.insert(ip)
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

    private static func ipv4(_ host: NWEndpoint.Host) -> String? {
        if case let .ipv4(address) = host { return "\(address)" }
        return nil
    }

    private func finishOnce() {
        guard !finished else { return }
        finished = true
        browsers.forEach { $0.cancel() }
        connections.forEach { $0.cancel() }
        finish(hosts.sorted())
    }
}
