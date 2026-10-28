import SwiftUI

struct TraktWatchlistRecovery: ViewModifier {
    let app: AppModel
    @Environment(\.scenePhase) private var scenePhase
    private var taskID: String {
        [app.accountOperationScope, String(app.storageReady), app.library.personalOwner, String(app.library.bookmarksReady), TraktAccountStore.forOwner(app.personalOwner).identity.uuidString,
         String(describing: scenePhase)].joined(separator: "|")
    }
    func body(content: Content) -> some View {
        content.task(id: taskID) {
            let owner = app.personalOwner, scope = app.accountOperationScope, account = TraktAccountStore.forOwner(owner)
            guard app.storageReady, app.library.bookmarksReady, app.library.personalOwner == owner else { app.library.bindTraktWatchlist(nil); return }
            if !account.ready {
                let identity = account.identity
                do { try account.load() } catch { app.library.bindTraktWatchlist(nil); Diagnostics.shared.recordFailure(error); return }
                if account.identity != identity { return }
            }
            let binding = TraktWatchlistSync(account: account, store: .forOwner(owner), active: { [weak app] in
                app?.storageReady == true && app?.personalOwner == owner && app?.accountOperationScope == scope
            })
            app.library.bindTraktWatchlist(binding)
            guard scenePhase == .active, let binding else { return }
            await binding.refresh()
        }
    }
}
