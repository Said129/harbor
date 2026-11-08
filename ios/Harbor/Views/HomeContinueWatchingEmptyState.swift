import SwiftUI

/// Desktop's `CWSection` empty state on Home: the row title and a dashed box with the sign-in prompt or the empty message.
struct HomeContinueWatchingEmptyState: View {
    let title: String
    let signedIn: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(HarborTheme.font(17, weight: .medium)).padding(.horizontal)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("continue-watching-title")
            Group {
                if signedIn {
                    Text(DesktopInterfaceText.value("Nothing in progress yet. Press Play on something."))
                } else {
                    Text("\(DesktopInterfaceText.value("Sign in to")) Stremio \(DesktopInterfaceText.value("to bring in your library."))")
                }
            }
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
