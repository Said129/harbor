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
    var body: some Scene { WindowGroup { HarborRootView(model: model) } }
}

@MainActor private struct HarborRootView: View {
    @Bindable var model: AppModel
    @State private var profileForeground = ProfileForegroundCycle()
    @AppStorage("uiLanguage") private var uiLanguage = "es"
    @AppStorage("cwSources") private var cwSources = ContinueWatchingSources.defaultValue
    @AppStorage("cwPerProfile") private var privateContinuing = false
    @Environment(\.scenePhase) private var scenePhase
    private var simklPlaybackTaskID: String {
        let token = SimklAccountStore.forOwner(model.personalOwner).session.map { EBookShelf.hash($0.accessToken) } ?? "disconnected"
        return [model.accountOperationScope, String(model.storageReady), cwSources, String(privateContinuing), String(model.sharesContinueSource), token, String(describing: scenePhase)].joined(separator: "|")
    }
    var body: some View {
        synchronization
            .sheet(isPresented: $model.showAccount, onDismiss: { model.accountDidDismiss() }) { accountSheet }
            .fullScreenCover(isPresented: $model.showProfiles) { profilesSheet }
    }
    private var content: some View {
            ZStack {
                if model.storageReady && model.profileContext.ready {
                    HarborShell(app: model).id(model.interfaceProfileScope)
                } else if model.profileContext.requiresSelection || model.switchingProfile {
                    profilesContent
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
    }
    private var persistence: some View {
        content
                .onOpenURL { model.openDocument($0) }
                .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { _ in
                    ProfileSettingsStore.shared.saveCurrent()
                }
                .onChange(of: scenePhase) { _, phase in if phase != .active { ProfileSettingsStore.shared.saveCurrent() } }
    }
    private var lifecycle: some View {
        persistence
                .task { _ = profileForeground.observe(active: scenePhase == .active); await model.start() }
                .onChange(of: scenePhase) { _, phase in
                    if profileForeground.observe(active: phase == .active) { model.requestProfilePromptOnReturn() }
                    if phase == .background { model.plugins.runtime?.sweep(trimIdle: true) }
                }
                .task(id: String(model.automaticProfilePromptPending) + "|" + String(describing: scenePhase) + "|" + String(model.profileContext.playback.hasActivePlayback)) {
                    await presentAutomaticProfilePrompt()
                }
                .task(id: String(model.storageReady) + "|" + model.settingsOwner) { if model.storageReady { await SportsReminderService.shared.removeOtherAccounts(owner: model.settingsOwner) } }
                .task(id: model.personalOwner) { MusicPlayback.shared.stopForAccount(model.personalOwner) }
                .onChange(of: model.accountOperationScope + "|" + String(model.storageReady)) { _, _ in model.plugins.invalidate(); model.readingPlugins.invalidate() }
    }
    private var synchronization: some View {
        lifecycle
                .task(id: model.personalOwner + "|" + String(model.storageReady)) {
                    guard model.storageReady else { return }
                    let account = SimklAccountStore.forOwner(model.personalOwner)
                    if !account.ready { do { try account.load() } catch { Diagnostics.shared.recordFailure(error) } }
                }
                .task(id: simklPlaybackTaskID) {
                    model.applyContinuePreferences()
                    let owner = model.personalOwner, scope = model.accountOperationScope, account = SimklAccountStore.forOwner(owner)
                    let feed = model.library.simklPlayback
                    feed.bind(account: account, scope: scope, active: { [weak model] in
                        model?.storageReady == true && model?.personalOwner == owner && model?.accountOperationScope == scope
                    }, enabled: { [weak model] in
                        ContinueWatchingSources(rawValue: UserDefaults.standard.string(forKey: "cwSources") ?? ContinueWatchingSources.defaultValue).simkl
                            && model?.library.continuingPrivate == false
                    })
                    guard scenePhase == .active, model.storageReady else { return }
                    await feed.refresh(focused: true, resume: model.sharedResume, dismissed: { model.library.isDismissed($0) })
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(300)) } catch { return }
                        await feed.refresh(resume: model.sharedResume, dismissed: { model.library.isDismissed($0) })
                    }
                }
                .task(id: model.harborIdentityOwner + "|" + model.interfaceProfileScope + "|" + String(model.storageReady) + "|" + String(describing: scenePhase)) {
                    guard scenePhase == .active, model.storageReady else { return }
                    let identity = model.harborIdentity
                    while !Task.isCancelled {
                        await identity.sync()
                        do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    }
                }
                .task(id: scenePhase) {
                    guard scenePhase == .active, model.storageReady else { return }
                    await model.library.sync()
                    await model.refreshAddons()
                }
                .modifier(LibraryPendingRecovery(app: model))
                .modifier(TraktPlaybackRecovery(app: model))
    }
    private var accountSheet: some View {
        NavigationStack { AccountView(app: model) }.font(HarborTheme.font()).foregroundStyle(HarborTheme.ink).tint(HarborTheme.accent).preferredColorScheme(.dark)
                        .environment(\.locale, Locale(identifier: InterfaceLanguage.resolve(uiLanguage)))
                        .environment(\.layoutDirection, InterfaceLanguage.resolve(uiLanguage) == "ar" ? .rightToLeft : .leftToRight)
    }
    private func presentAutomaticProfilePrompt() async {
        guard scenePhase == .active, model.automaticProfilePromptPending, !model.profileContext.playback.hasActivePlayback else { return }
        while !Task.isCancelled && model.automaticProfilePromptPending {
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
            let root = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
            if root?.viewIfLoaded?.window != nil, root?.presentedViewController == nil, model.presentDeferredProfilePrompt() { return }
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
        }
    }
    private var profilesSheet: some View {
        profilesContent.presentationBackground(.clear)
    }
    private var profilesContent: some View {
        HouseholdProfilesView(app: model)
            .preferredColorScheme(.dark)
            .environment(\.locale, Locale(identifier: InterfaceLanguage.resolve(uiLanguage)))
            .environment(\.layoutDirection, InterfaceLanguage.resolve(uiLanguage) == "ar" ? .rightToLeft : .leftToRight)
    }
}
