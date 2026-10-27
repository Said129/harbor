import SwiftUI

struct TraktPlaybackRecovery: ViewModifier {
    let app: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("cwSources") private var sources = ContinueWatchingSources.defaultValue
    @AppStorage("cwPerProfile") private var privateContinuing = false
    private var taskID: String {
        [app.accountOperationScope, String(app.storageReady), sources, String(privateContinuing), String(app.sharesContinueSource),
         TraktAccountStore.forOwner(app.personalOwner).identity.uuidString, String(describing: scenePhase)].joined(separator: "|")
    }
    func body(content: Content) -> some View {
        content.task(id: taskID) {
            let owner = app.personalOwner, scope = app.accountOperationScope, account = TraktAccountStore.forOwner(owner), foreground = scenePhase == .active
            let feed = app.library.traktPlayback
            let enabled: TraktClient.Active = { [weak app] in
                ContinueWatchingSources(rawValue: UserDefaults.standard.string(forKey: "cwSources") ?? ContinueWatchingSources.defaultValue).trakt
                    && app?.library.continuingPrivate == false
                    && !(UserDefaults.standard.bool(forKey: "cwPerProfile") && app?.sharesContinueSource == true)
            }
            if app.storageReady && enabled() && !account.ready { do { try account.load() } catch { Diagnostics.shared.recordFailure(error) } }
            feed.bind(account: account, scope: scope, active: { [weak app] in
                foreground && app?.storageReady == true && app?.personalOwner == owner && app?.accountOperationScope == scope
            }, enabled: enabled)
            guard foreground, app.storageReady, enabled() else { return }
            await feed.refresh(focused: true, resume: app.sharedResume, dismissed: { app.library.isDismissed($0) })
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(300)) } catch { return }
                await feed.refresh(resume: app.sharedResume, dismissed: { app.library.isDismissed($0) })
            }
        }
    }
}
