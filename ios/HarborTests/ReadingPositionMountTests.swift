import XCTest
import SwiftUI
import Observation
import UIKit
@testable import Harbor

@MainActor @Observable private final class MountedReadingPosition {
    var block = 14
    var jump: EBookReadingJump?
}
private struct MountedReadingContent: View {
    let state: MountedReadingPosition
    private let blocks = (0..<60).map { EBookBlock(id: $0, text: "Paragraph \($0). " + String(repeating: "Actual readable chapter text. ", count: 10)) }
    var body: some View {
        EBookContinuousReaderView(blocks: blocks, spacing: 19, pageWidth: 520, margin: 22,
            jump: state.jump, block: Binding(get: { state.block }, set: { state.block = $0 })) { item in
            Text(item.text).font(.system(size: 19)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

@MainActor final class ReadingPositionMountTests: XCTestCase {
    func testActualMountedNativeScrollRestoresThePrintedParagraphThenJumpsAndAcceptsScrollingBack() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let state = MountedReadingPosition(), window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        let host = UIHostingController(rootView: MountedReadingContent(state: state))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        let scroll = try await waitForScroll(host.view)
        try await wait(stage: "initial paragraph14 restoration", condition: { scroll.contentOffset.y > 200 && state.block == 14 }, status: { "block=\(state.block) offset=\(scroll.contentOffset) content=\(scroll.contentSize) viewport=\(scroll.bounds.size)" })
        let initialOffset = scroll.contentOffset.y
        state.block = 30; state.jump = EBookReadingJump(block: 30)
        try await wait(stage: "explicit paragraph30 jump", condition: { scroll.contentOffset.y > initialOffset + 100 && state.block == 30 }, status: { "block=\(state.block) offset=\(scroll.contentOffset) previous=\(initialOffset)" })
        scroll.setContentOffset(.zero, animated: false)
        try await wait(stage: "native scrolling back to paragraph0", condition: { scroll.contentOffset.y < 1 && state.block == 0 }, status: { "block=\(state.block) offset=\(scroll.contentOffset)" })
        XCTAssertGreaterThan(scroll.bounds.width, 100); XCTAssertGreaterThan(scroll.bounds.height, 100)
        print("Actual mounted continuous reader: printed paragraph14 restored, jump30 visible, native scroll back0 published")
    }
    private func waitForScroll(_ root: UIView) async throws -> UIScrollView {
        var scroll: UIScrollView?
        try await wait(stage: "native scroll view creation", condition: { scroll = self.findScroll(root); return scroll != nil }, status: { "host=\(root.bounds)" })
        return try XCTUnwrap(scroll)
    }
    private func findScroll(_ view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        return view.subviews.lazy.compactMap(findScroll).first
    }
    private func wait(stage: String, condition: () -> Bool, status: () -> String, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<100 {
            if condition() { print("Mounted reader stage passed: " + stage + "; " + status()); return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Mounted reader stage failed: " + stage + "; " + status(), file: file, line: line)
        throw HarborError(code: "reader-position-test-timeout")
    }
}
