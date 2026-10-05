import SwiftUI
import UIKit

@MainActor
final class HarborAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        _ = DownloadManager.shared
        return true
    }
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == DownloadManager.sessionIdentifier else { completionHandler(); return }
        DownloadManager.shared.handleBackgroundEvents(completionHandler)
    }
}

@main
struct HarborApp: App {
    @UIApplicationDelegateAdaptor(HarborAppDelegate.self) private var delegate
    @State private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            HarborShell(app: model).font(HarborTheme.font()).foregroundStyle(HarborTheme.ink).tint(HarborTheme.accent).preferredColorScheme(.dark)
                .task { await model.start() }
                .sheet(isPresented: $model.showAccount) { NavigationStack { AccountView(app: model) } }
        }
    }
}
