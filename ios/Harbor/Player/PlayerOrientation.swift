import SwiftUI
import UIKit

/// Scope the requested orientation to the playback presentation, including its
/// connecting screen and sheets. Overlapping presentations share the lease so
/// changing episode does not briefly rotate the app back to portrait.
@MainActor
enum PlayerOrientation {
    @MainActor private final class Presentation {
        weak var window: UIWindow?
        let previous: UIInterfaceOrientationMask
        var leases = Set<UUID>()
        init(window: UIWindow) {
            self.window = window
            switch window.windowScene?.interfaceOrientation {
            case .landscapeLeft: previous = .landscapeLeft
            case .landscapeRight: previous = .landscapeRight
            default: previous = .portrait
            }
        }
    }
    private static var presentations: [ObjectIdentifier: Presentation] = [:]

    static func supportedOrientations(for window: UIWindow?) -> UIInterfaceOrientationMask {
        guard let window, presentations[ObjectIdentifier(window)] != nil else { return .allButUpsideDown }
        return .landscape
    }

    static func begin(in window: UIWindow) -> UUID {
        let key = ObjectIdentifier(window)
        let presentation = presentations[key] ?? Presentation(window: window)
        let lease = UUID()
        presentation.leases.insert(lease)
        presentations[key] = presentation
        request(.landscape, in: window)
        return lease
    }

    static func end(_ lease: UUID) {
        guard let (key, presentation) = presentations.first(where: { $0.value.leases.contains(lease) }) else { return }
        presentation.leases.remove(lease)
        guard presentation.leases.isEmpty else { return }
        presentations.removeValue(forKey: key)
        if let window = presentation.window { request(presentation.previous, in: window) }
    }

    private static func request(_ orientations: UIInterfaceOrientationMask, in window: UIWindow) {
        guard let scene = window.windowScene else { return }
        var controller = window.rootViewController
        while let current = controller {
            current.setNeedsUpdateOfSupportedInterfaceOrientations()
            controller = current.presentedViewController
        }
        // Explicit geometry requests also work when sensor-driven autorotation
        // is locked. No UIDevice KVC or change to the user's system setting.
        UIView.performWithoutAnimation {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) { error in
                Diagnostics.shared.record(.failure, count: (error as NSError).code)
            }
        }
    }
}

struct PlayerOrientationAnchor: UIViewControllerRepresentable {
    var enabled = true
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.enabled = enabled
        controller.updateOrientation()
    }
    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) { controller.releaseOrientation() }

    final class Controller: UIViewController {
        var enabled = true
        private var lease: UUID?
        override func loadView() {
            let anchor = WindowAnchor()
            anchor.owner = self; anchor.isUserInteractionEnabled = false
            view = anchor
        }
        override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); updateOrientation() }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); updateOrientation() }
        func updateOrientation() {
            if !enabled { releaseOrientation(); return }
            guard lease == nil, let window = viewIfLoaded?.window else { return }
            lease = PlayerOrientation.begin(in: window)
        }
        func releaseOrientation() {
            if let lease { PlayerOrientation.end(lease); self.lease = nil }
        }
    }

    private final class WindowAnchor: UIView {
        weak var owner: Controller?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            // Acquire as soon as UIKit attaches the presentation. Waiting for
            // viewDidAppear would defer rotation until its transition finishes.
            owner?.updateOrientation()
        }
    }
}
