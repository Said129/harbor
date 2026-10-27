import XCTest
import SwiftUI
import Observation
import Network
import UIKit
@testable import Harbor

@MainActor @Observable private final class MountedPosterState {
    var requestedFocus: Int?
    var observedFocus: Int?
    var nativeEnvironmentFocus: [Int: Bool] = [:]
    var widths: [Int: CGFloat] = [:]
    var activations = 0
}
private struct MountedNativePosterFocusProbe: View {
    let index: Int
    let state: MountedPosterState
    let media: Media
    @Environment(\.isFocused) private var focused
    var body: some View {
        ProfilePoster(media: media, width: 116, artworkFallbacks: [], honorsRowStyle: true,
            onExpansionWidthChange: { state.widths[index] = $0 })
            .onChange(of: focused, initial: true) { _, value in state.nativeEnvironmentFocus[index] = value }
    }
}
private struct MountedPosterRow: View {
    let state: MountedPosterState
    let row: PosterRowContext
    let media: [Media]
    @FocusState private var focused: Int?
    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(media.enumerated()), id: \.offset) { index, item in
                    VStack(spacing: 0) {
                        MountedNativePosterFocusProbe(index: index, state: state, media: item)
                    }
                        .contentShape(Rectangle()).onTapGesture { state.activations += 1 }
                        // isFocused describes the nearest focusable ancestor.
                        // Focus the control container, leaving the production
                        // poster inside it just as it is inside a NavigationLink.
                        .focusable(interactions: .edit).focused($focused, equals: index)
                }
            }.padding(.horizontal, 16).padding(.vertical, 20)
        }.posterRowBehavior(context: row).frame(height: 250)
            .onChange(of: state.requestedFocus) { _, value in focused = value }
            .onChange(of: focused) { _, value in state.observedFocus = value }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background(.black)
    }
}

@MainActor final class PosterBehaviorMountTests: XCTestCase {
    func testActualNativeFocusLoadsWidePixelsReservesWidthRevealsTheCardAndCollapsesForPointerWithoutActivatingIt() async throws {
        XCTAssertEqual(UIDevice.current.userInterfaceIdiom, .pad, "UIKit keyboard navigation is an iPad interaction; the iPhone scene did not provide a focus system")
        let defaults = UserDefaults.standard
        let keys = ["posterFocusedCard", "posterBackdropExpansion", "posterDockMagnification", "posterDockTransitionMs", "rowCardStyle", "posterScale", "posterRadius", "posterEffect", "posterQuality"]
        let old = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        defer { for key in keys { if let value = old[key] ?? nil { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } } }
        for key in keys.prefix(3) { defaults.set(true, forKey: key) }
        defaults.set("poster", forKey: "rowCardStyle"); defaults.set(1.0, forKey: "posterScale"); defaults.set(12.0, forKey: "posterRadius")
        defaults.set("off", forKey: "posterEffect"); defaults.set("high", forKey: "posterQuality")
        PosterAttentionState.shared.pointerMoved(); PosterAttentionState.shared.input = .keyboard
        let server = try OwnedPosterImagePublisher(poster: png(700, 1050, .red), wide: png(1024, 576, .green))
        let base = try await server.start(); defer { server.stop() }
        let media = (0..<3).map { index in
            var item = Media(id: "mounted-poster-\(UUID().uuidString)", type: "movie", name: "Owned card \(index)")
            item.poster = base + "/poster.png"; item.background = base + "/wide.png"; return item
        }
        let state = MountedPosterState(), row = PosterRowContext()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        let host = UIHostingController(rootView: MountedPosterRow(state: state, row: row, media: media).preferredColorScheme(.dark))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey(); PosterAttentionState.shared.pointerMoved() }
        defer {
            if (testRun?.failureCount ?? 0) > 0 {
                capture(window, "poster-behavior-native-failed-stage")
                let diagnostic = XCTAttachment(string: "requested=\(String(describing: state.requestedFocus)); observed=\(String(describing: state.observedFocus)); nativeEnvironment=\(state.nativeEnvironmentFocus); input=\(PosterAttentionState.shared.input); active=\(String(describing: PosterAttentionState.shared.active)); widths=\(state.widths); viewport=\(row.viewport); frames=\(row.frames)\n" + nativeFocusSummary(window))
                diagnostic.name = "poster-behavior-native-state"; diagnostic.lifetime = .keepAlways; add(diagnostic)
            }
        }
        try await wait("three real measured cards") { row.frames.count == 3 && row.viewport.width > 300 }
        let original = row.frames.values.sorted { $0.minX < $1.minX }
        XCTAssertTrue(original.allSatisfy { abs($0.width - 116) < 1 })
        capture(window, "poster-behavior-native-initial")
        state.requestedFocus = 0
        try await wait("actual native row focus binding") { state.observedFocus == 0 }
        // Complete pending native focus work as UIKit requires. This does not
        // substitute the binding value for the production environment value.
        host.setNeedsFocusUpdate(); host.updateFocusIfNeeded(); scene.focusSystem?.updateFocusIfNeeded()
        try await wait("the actual iPad scene provides a native keyboard focus system") { scene.focusSystem != nil }
        try await wait("focused production poster receives the native focus environment") { PosterAttentionState.shared.active != nil }
        try await wait("decoded wide artwork reserves the expanded width") { (state.widths[0] ?? 0) > 300 }
        try await Task.sleep(for: .milliseconds(650))
        let expanded = row.frames.values.sorted { $0.minX < $1.minX }
        XCTAssertEqual(expanded[0].width, 174 * 16 / 9, accuracy: 2)
        XCTAssertEqual(expanded[0].height, original[0].height, accuracy: 2)
        XCTAssertGreaterThan(expanded[1].minX, original[1].minX + 180)
        XCTAssertEqual(state.activations, 0); capture(window, "poster-behavior-native-focused-wide")
        state.requestedFocus = 2
        try await wait("last card expansion and native viewport reveal") {
            guard state.observedFocus == 2, let width = state.widths[2], width > 300,
                  let frame = row.frames[PosterAttentionState.shared.active ?? UUID()] else { return false }
            return frame.minX >= 11 && frame.maxX <= row.viewport.maxX - 11
        }
        XCTAssertEqual(state.activations, 0); capture(window, "poster-behavior-native-revealed-last")
        PosterAttentionState.shared.pointerMoved()
        try await wait("pointer cancels keyboard expansion and viewport reveal") { state.widths.isEmpty && row.reveal == nil && PosterAttentionState.shared.active == nil && row.frames.values.allSatisfy { abs($0.width - 116) < 0.01 } }
        var previousFrames: [UUID: CGRect] = [:], stableSamples = 0
        try await wait("collapsed cells finish their native layout animation") {
            stableSamples = previousFrames == row.frames ? stableSamples + 1 : 0
            previousFrames = row.frames; return stableSamples >= 4
        }
        let frame = try XCTUnwrap(row.frames.values.first(where: { $0.midX > 0 && $0.midX < row.viewport.width }))
        let beforeDock = row.frames
        row.pointerX = frame.midX
        try await Task.sleep(for: .milliseconds(850))
        XCTAssertEqual(row.frames, beforeDock, "Pointer magnification must preserve the actual layout cells")
        capture(window, "poster-behavior-native-pointer-dock")
        row.pointerX = nil; state.requestedFocus = nil
        try await wait("native focus leaves the row") { state.observedFocus == nil }
        XCTAssertEqual(state.activations, 0)
    }
    private func png(_ width: CGFloat, _ height: CGFloat, _ color: UIColor) -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: .init(width: width, height: height), format: format).pngData { context in
            color.setFill(); context.fill(.init(x: 0, y: 0, width: width, height: height))
        }
    }
    private func nativeFocusSummary(_ window: UIWindow) -> String {
        var lines = ["applicationState=\(UIApplication.shared.applicationState.rawValue); scene=\(String(describing: window.windowScene?.activationState)); key=\(window.isKeyWindow); hidden=\(window.isHidden); focusSystem=\(String(describing: window.windowScene?.focusSystem)); focusedItem=\(String(describing: window.windowScene?.focusSystem?.focusedItem))"]
        func visit(_ view: UIView, depth: Int) {
            guard lines.count < 100 else { return }
            lines.append("depth=\(depth); class=\(String(describing: type(of: view))); canBecomeFocused=\(view.canBecomeFocused); isFocused=\(view.isFocused); frame=\(view.frame); hidden=\(view.isHidden); alpha=\(view.alpha)")
            for child in view.subviews { visit(child, depth: depth + 1) }
        }
        visit(window, depth: 0); return lines.joined(separator: "\n")
    }
    private func capture(_ window: UIWindow, _ name: String) {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func wait(_ stage: String, condition: () -> Bool) async throws {
        for _ in 0..<100 { if condition() { return }; try await Task.sleep(for: .milliseconds(50)) }
        XCTFail("Mounted production poster stage failed: " + stage); throw HarborError(code: "owned-poster-mount-timeout")
    }
}

final class OwnedPosterImagePublisher: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "harbor.owned.poster-images")
    private let poster: Data, wide: Data
    private var started = false
    init(poster: Data, wide: Data) throws {
        self.poster = poster; self.wide = wide
        let parameters = NWParameters.tcp; parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }
    func start() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [self] state in
                guard !started else { return }
                switch state {
                case .ready:
                    started = true
                    if let port = listener.port { continuation.resume(returning: "http://127.0.0.1:\(port.rawValue)") }
                    else { continuation.resume(throwing: HarborError(code: "owned-poster-listener-port")) }
                case .failed(let error): started = true; continuation.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [self] connection in connection.start(queue: queue); receive(connection, request: Data()) }
            listener.start(queue: queue)
        }
    }
    private func receive(_ connection: NWConnection, request: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [self] chunk, _, ended, error in
            var data = request; if let chunk { data.append(chunk) }
            guard error == nil, data.count <= 16 * 1024 else { connection.cancel(); return }
            guard data.range(of: Data("\r\n\r\n".utf8)) != nil else {
                if ended { connection.cancel() } else { receive(connection, request: data) }; return
            }
            let body = String(decoding: data, as: UTF8.self).hasPrefix("GET /wide.png ") ? wide : poster
            let header = "HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
        }
    }
    func stop() { listener.cancel() }
}
