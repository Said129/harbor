import SwiftUI

struct TraktWatchedRecovery: ViewModifier {
    let app: AppModel
    @Environment(\.scenePhase) private var scenePhase
    private var taskID: String {
        [app.accountOperationScope, app.library.personalOwner, String(app.storageReady), String(app.library.bookmarksReady),
         TraktAccountStore.forOwner(app.personalOwner).identity.uuidString, String(describing: scenePhase)].joined(separator: "|")
    }
    func body(content: Content) -> some View {
        content.task(id: taskID) {
            let owner = app.personalOwner, scope = app.accountOperationScope, account = TraktAccountStore.forOwner(owner)
            guard app.storageReady, app.library.bookmarksReady, app.library.personalOwner == owner else { app.library.traktWatched.clear(); return }
            if !account.ready {
                let identity = account.identity
                do { try account.load() } catch { app.library.traktWatched.clear(); Diagnostics.shared.recordFailure(error); return }
                if account.identity != identity { return }
            }
            app.library.traktWatched.bind(account: account, scope: scope, active: { [weak app] in
                app?.storageReady == true && app?.personalOwner == owner && app?.accountOperationScope == scope
            })
            if scenePhase == .active { await app.library.traktWatched.refresh() }
        }
    }
}
