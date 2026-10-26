import XCTest
@testable import Harbor

private struct PosterBehaviorReference: Decodable {
    struct Transform: Decodable { let x, y, scale, zIndex: Double; let origin: String }
    struct Card: Decodable { let index: Int; let left, width: Double; let active: Bool; let expected: Transform; let transition: String? }
    struct Dock: Decodable { let rtl: Bool; let pointerX, viewportLeft, viewportWidth: Double; let transitionMs: Double?; let reset: Bool; let cards: [Card] }
    struct Size: Decodable { let width, height: Double; let expected: Bool }
    struct Reveal: Decodable { let left, right, viewportLeft, viewportRight, gutter, expected: Double }
    struct Identity: Decodable { let current: String; let candidates: [String]; let expected: String? }
    struct Width: Decodable { let height, expected: Double }
    struct Rung: Decodable { let input, expected: String }
    let actual_original_typescript_executed: Bool
    let dockCases: [Dock]; let sizes: [Size]; let reveals: [Reveal]; let identities: [Identity]; let widths: [Width]; let rungs: [Rung]
}

final class PosterBehaviorTests: XCTestCase {
    private func reference() throws -> PosterBehaviorReference {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "poster-behavior-reference", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(PosterBehaviorReference.self, from: Data(contentsOf: url))
        XCTAssertTrue(fixture.actual_original_typescript_executed); return fixture
    }
    func testDockMatchesTheExecutedDesktopTransformsAtBothEdgesWithRTLScrollingAndDurationBounds() throws {
        let fixture = try reference(); XCTAssertEqual(fixture.dockCases.count, 24)
        for entry in fixture.dockCases {
            XCTAssertTrue(entry.reset)
            for card in entry.cards {
                let value = PosterBehaviorPolicy.dock(pointerX: entry.pointerX,
                    frame: CGRect(x: card.left, y: 0, width: card.width, height: 180),
                    viewport: CGRect(x: entry.viewportLeft, y: 0, width: entry.viewportWidth, height: 200), first: card.index == 0, last: card.index == 5, rtl: entry.rtl)
                let message = "rtl=\(entry.rtl) pointer=\(entry.pointerX) index=\(card.index)"
                XCTAssertEqual(value.x, card.expected.x, accuracy: 0.000001, message)
                XCTAssertEqual(value.y, card.expected.y, accuracy: 0.000001, message)
                XCTAssertEqual(value.scale, card.expected.scale, accuracy: 0.000001, message)
                XCTAssertEqual(value.zIndex, card.expected.zIndex, message); XCTAssertEqual(value.origin.rawValue, card.expected.origin, message)
                if let transition = card.transition {
                    let duration = Int(PosterBehaviorPolicy.transitionMilliseconds(entry.transitionMs ?? .nan))
                    XCTAssertEqual(transition, "transform \(duration)ms cubic-bezier(0.22, 0.61, 0.36, 1)")
                }
            }
        }
        XCTAssertEqual(PosterBehaviorPolicy.dock(pointerX: nil, frame: .zero, viewport: .zero, first: true, last: true, rtl: false), PosterDockTransform())
    }
    func testWideArtworkEligibilityIdentityWidthAndRevealMatchTheOriginalBoundaryCases() throws {
        let fixture = try reference()
        for item in fixture.sizes { XCTAssertEqual(PosterBehaviorPolicy.suitableWideImage(width: item.width, height: item.height), item.expected) }
        for item in fixture.widths { XCTAssertEqual(PosterBehaviorPolicy.expandedWidth(posterHeight: item.height), item.expected, accuracy: 0.000001) }
        for item in fixture.reveals {
            XCTAssertEqual(PosterBehaviorPolicy.scrollDelta(card: CGRect(x: item.left, y: 0, width: item.right - item.left, height: 1),
                viewport: CGRect(x: item.viewportLeft, y: 0, width: item.viewportRight - item.viewportLeft, height: 1), gutter: item.gutter), item.expected)
        }
        for item in fixture.identities { XCTAssertEqual(PosterBehaviorPolicy.alternatives(item.candidates, poster: item.current).first, item.expected.map(PosterBehaviorPolicy.wideRung)) }
        for item in fixture.rungs { XCTAssertEqual(PosterBehaviorPolicy.wideRung(item.input), item.expected) }
    }
}
