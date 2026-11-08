import SwiftUI

/// Desktop's genre pill on the detail page: a TMDB genre opens its genre-filtered list, and any other name stays plain text.
struct DetailGenrePill: View {
    let genre: String
    let isSeries: Bool
    let app: AppModel

    var body: some View {
        if let rail = DetailGenreRules.browseRail(for: genre, isSeries: isSeries) {
            NavigationLink {
                DiscoveryGrid(rail: rail, app: app, titleOverride: genre)
            } label: {
                label
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("detail-genre-pill")
        } else {
            label
        }
    }

    private var label: some View {
        Text(genre)
            .font(HarborTheme.font(11, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.5), in: .capsule)
    }
}
