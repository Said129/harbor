import SwiftUI

/// Desktop's folded corner mark (`top-ten-ribbon.tsx`), sized as a share of the poster and aligned to its logical edge.
struct TopTenCornerRibbon: View {
    let side: String

    private var alignment: Alignment { side == "left" ? .topLeading : .topTrailing }
    private var imageName: String { side == "left" ? "top10-ribbon-left" : "top10-ribbon-right" }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: alignment) {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: min(geometry.size.width * 0.17, 36))
                    .shadow(color: .black.opacity(0.45), radius: 7, x: 0, y: 3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 4)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DesktopInterfaceText.value("Top 10"))
        .accessibilityIdentifier("poster-top10-ribbon")
    }
}
