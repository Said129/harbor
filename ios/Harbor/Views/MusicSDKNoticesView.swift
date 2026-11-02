import SwiftUI

struct MusicSDKNoticesView: View {
    var resourceName = "SpotifySDKNotices"
    var title = "Spotify SDK"
    private var notice: String {
        guard let file = Bundle.main.url(forResource: resourceName, withExtension: "txt") else { return "" }
        return (try? String(contentsOf: file, encoding: .utf8)) ?? ""
    }
    var body: some View {
        ScrollView {
            Text(verbatim: notice).font(.callout).textSelection(.enabled)
                .frame(maxWidth: 820, alignment: .leading).frame(maxWidth: .infinity).padding(20)
        }.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .background(HarborTheme.background).foregroundStyle(HarborTheme.ink)
    }
}
