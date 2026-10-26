import SwiftUI
import UIKit

/// A fitted logo keeps its aspect ratio and logical alignment inside bounded art.
struct AlignedArtworkImage: UIViewRepresentable {
    let image: UIImage
    let alignment: UnitPoint
    @Environment(\.layoutDirection) private var direction
    func makeUIView(context: Context) -> FittedArtworkView { FittedArtworkView(frame: .zero) }
    func updateUIView(_ view: FittedArtworkView, context: Context) {
        view.image = image
        view.alignment = UnitPoint(x: direction == .rightToLeft ? 1 - alignment.x : alignment.x, y: alignment.y)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: FittedArtworkView, context: Context) -> CGSize? { proposal.replacingUnspecifiedDimensions() }
}

final class FittedArtworkView: UIView {
    let imageView = UIImageView()
    var image: UIImage? { didSet { imageView.image = image; setNeedsLayout() } }
    var alignment: UnitPoint = .center { didSet { setNeedsLayout() } }
    override init(frame: CGRect) { super.init(frame: frame); prepare() }
    required init?(coder: NSCoder) { super.init(coder: coder); prepare() }
    private func prepare() {
        clipsToBounds = true; isAccessibilityElement = false
        imageView.isAccessibilityElement = false; imageView.contentMode = .scaleToFill; addSubview(imageView)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let image, image.size.width > 0, image.size.height > 0, bounds.width > 0, bounds.height > 0 else { imageView.frame = .zero; return }
        let factor = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
        imageView.frame = CGRect(x: (bounds.width - size.width) * alignment.x, y: (bounds.height - size.height) * alignment.y, width: size.width, height: size.height)
    }
}
