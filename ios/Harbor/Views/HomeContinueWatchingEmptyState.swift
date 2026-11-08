import SwiftUI

/// Desktop's `CWSection` empty state on Home: the row title and a dashed box with the empty message.
/// Desktop's signed-out variant invites a Stremio sign-in, which iOS does not have (profiles use local sources), so both cases show the empty message.
struct HomeContinueWatchingEmptyState: View {
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(HarborTheme.font(17, weight: .medium)).padding(.horizontal)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("continue-watching-title")
            Text(DesktopInterfaceText.value("Nothing in progress yet. Press Play on something."))
                .font(HarborTheme.font(15))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
                .padding(.horizontal, 24)
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4])).foregroundStyle(Color.secondary.opacity(0.5)))
                .padding(.horizontal)
        }
    }
}
