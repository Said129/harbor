import SwiftUI
import UIKit
import UserNotifications

@MainActor
final class HarborAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        PlayerOrientation.supportedOrientations(for: window)
    }
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        _ = DownloadManager.shared
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == DownloadManager.sessionIdentifier else { completionHandler(); return }
        DownloadManager.shared.handleBackgroundEvents(completionHandler)
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .list, .sound]) }
}

@main
struct HarborApp: App {
    @UIApplicationDelegateAdaptor(HarborAppDelegate.self) private var delegate
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            HarborShell(app: model).font(HarborTheme.font()).foregroundStyle(HarborTheme.ink).tint(HarborTheme.accent).preferredColorScheme(.dark)
                .task { await model.start() }
                .task(id: String(model.storageReady) + "|" + (model.user?.id ?? "guest")) { if model.storageReady { await SportsReminderService.shared.removeOtherAccounts(owner: model.user?.id ?? "guest") } }
                .task(id: model.user?.id ?? "guest") { MusicPlayback.shared.stopForAccount(model.user?.id ?? "guest") }
                .task(id: (model.user?.id ?? "guest") + "|" + String(describing: scenePhase)) {
                    guard scenePhase == .active else { return }
                    let profile = ProfilePreferences.forOwner(model.user?.id ?? "guest")
                    while !Task.isCancelled {
                        await profile.cloud.sync()
                        do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    }
                }
                .task(id: scenePhase) {
                    guard scenePhase == .active, model.storageReady else { return }
                    await model.library.sync()
                }
                .sheet(isPresented: $model.showAccount) { NavigationStack { AccountView(app: model) }.font(HarborTheme.font()).foregroundStyle(HarborTheme.ink).tint(HarborTheme.accent).preferredColorScheme(.dark) }
        }
    }
}
