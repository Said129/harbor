import SwiftUI
import Combine
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
    @AppStorage("uiLanguage") private var uiLanguage = "es"
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            ZStack {
                if model.storageReady && model.profileContext.ready {
                    HarborShell(app: model).id(model.interfaceProfileScope)
                } else {
                    HarborTheme.background.ignoresSafeArea()
                    VStack(spacing: 20) {
                        HarborBrand(size: 36)
                        if let error = model.error {
                            Text(error).font(HarborTheme.font(14)).multilineTextAlignment(.center).foregroundStyle(.secondary)
                            Button(DesktopInterfaceText.value("Retry")) { Task { await model.retryStartup() } }
                                .buttonStyle(HarborAccountButtonStyle()).accessibilityIdentifier("profile-startup-retry")
                        } else { HarborLoader().frame(width: 64, height: 64).accessibilityIdentifier("profile-startup-loader") }
                    }.padding(30)
                }
            }.font(HarborTheme.font()).foregroundStyle(HarborTheme.ink).tint(HarborTheme.accent).preferredColorScheme(.dark)
                .onOpenURL { model.openDocument($0) }
                .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { _ in
                    ProfileSettingsStore.shared.saveCurrent()
                }
                .onChange(of: scenePhase) { _, phase in if phase != .active { ProfileSettingsStore.shared.saveCurrent() } }
                .task { await model.start() }
                .task(id: String(model.storageReady) + "|" + model.settingsOwner) { if model.storageReady { await SportsReminderService.shared.removeOtherAccounts(owner: model.settingsOwner) } }
                .task(id: model.personalOwner) { MusicPlayback.shared.stopForAccount(model.personalOwner) }
                .task(id: model.harborIdentityOwner + "|" + model.interfaceProfileScope + "|" + String(model.storageReady) + "|" + String(describing: scenePhase)) {
                    guard scenePhase == .active, model.storageReady else { return }
                    let profile = model.harborIdentity
                    while !Task.isCancelled {
                        await profile.cloud.sync()
                        do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    }
                }
                .task(id: scenePhase) {
                    guard scenePhase == .active, model.storageReady else { return }
                    await model.library.sync()
                    await model.refreshAddons()
                }
                .sheet(isPresented: $model.showAccount) { NavigationStack { AccountView(app: model) }.font(HarborTheme.font()).foregroundStyle(HarborTheme.ink).tint(HarborTheme.accent).preferredColorScheme(.dark)
                        .environment(\.locale, Locale(identifier: InterfaceLanguage.resolve(uiLanguage)))
                        .environment(\.layoutDirection, InterfaceLanguage.resolve(uiLanguage) == "ar" ? .rightToLeft : .leftToRight) }
        }
    }
}
