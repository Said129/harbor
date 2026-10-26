import XCTest
import SwiftUI
import UIKit
@testable import Harbor

@MainActor final class FittedArtworkTests: XCTestCase {
    func testNativeFittedLogosAlignWithinTheClippedViewportWithoutStretching() {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }
        let view = FittedArtworkView(frame: CGRect(x: 0, y: 0, width: 200, height: 80)); view.image = image
        for (alignment, x) in [(UnitPoint.leading, 0.0), (.center, 60.0), (.trailing, 120.0)] {
            view.alignment = alignment; view.layoutIfNeeded()
            XCTAssertEqual(view.imageView.frame, CGRect(x: x, y: 0, width: 80, height: 80))
        }
        view.frame.size = CGSize(width: 80, height: 200); view.alignment = .bottomTrailing; view.layoutIfNeeded()
        XCTAssertEqual(view.imageView.frame, CGRect(x: 0, y: 120, width: 80, height: 80)); XCTAssertTrue(view.clipsToBounds)
        view.image = nil; view.layoutIfNeeded(); XCTAssertEqual(view.imageView.frame, .zero)
    }
}
