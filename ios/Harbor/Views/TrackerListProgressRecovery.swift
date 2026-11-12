import SwiftUI

/// Keeps the AniList and MyAnimeList list progress filled while the app is active, so the watched marks of
/// `LibraryModel.watchedEpisodes` do not wait for a lists screen to be opened.
struct TrackerListProgressRecovery: ViewModifier {
    let app: AppModel
    @Environment(\.scenePhase) private var scenePhase
    private var taskID: String {
        [String(app.storageReady), app.personalOwner, String(describing: scenePhase)].joined(separator: "|")
    }
    func body(content: Content) -> some View {
        content.task(id: taskID) {
            guard scenePhase == .active, app.storageReady else { return }
            await TrackerListProgressLoader.refresh(owner: app.personalOwner)
        }
    }
}
