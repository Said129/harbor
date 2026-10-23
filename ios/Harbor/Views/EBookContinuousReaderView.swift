import SwiftUI

/// A newly mounted continuous reader owns its scroll binding. The printed reader
/// publishes a paragraph, not the transient position of a removed scroll view.
struct EBookContinuousReaderView<Content: View>: View {
    let blocks: [EBookBlock]
    let spacing: Double
    let pageWidth: Double
    let margin: Double
    let jump: EBookReadingJump?
    let content: (EBookBlock) -> Content
    @Binding private var block: Int
    @State private var position: Int?
    @State private var initialBlock: Int
    @State private var mounting = true

    init(blocks: [EBookBlock], spacing: Double, pageWidth: Double, margin: Double,
         jump: EBookReadingJump?, block: Binding<Int>, @ViewBuilder content: @escaping (EBookBlock) -> Content) {
        self.blocks = blocks; self.spacing = spacing; self.pageWidth = pageWidth; self.margin = margin
        self.jump = jump; self.content = content; _block = block
        _position = State(initialValue: block.wrappedValue); _initialBlock = State(initialValue: block.wrappedValue)
    }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: spacing) {
                    ForEach(blocks) { item in content(item).frame(maxWidth: .infinity, alignment: .leading).id(item.id) }
                }.scrollTargetLayout().frame(maxWidth: pageWidth).frame(maxWidth: .infinity)
                    .padding(.horizontal, margin).padding(.vertical, 24)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("ebook-reader-scroll")
                .scrollPosition(id: $position, anchor: .top)
                .task {
                    // The original paragraph must survive the first layout of a
                    // different reading mode, including a landscape iPad spread.
                    await Task.yield()
                    guard !Task.isCancelled, blocks.contains(where: { $0.id == initialBlock }) else { mounting = false; return }
                    position = initialBlock; proxy.scrollTo(initialBlock, anchor: .top)
                    mounting = false
                }
                .onChange(of: position) { _, value in
                    guard !mounting, let value, blocks.contains(where: { $0.id == value }) else { return }
                    block = value
                }
                .onChange(of: jump?.id) { _, _ in
                    guard let jump, blocks.contains(where: { $0.id == jump.block }) else { return }
                    position = jump.block; proxy.scrollTo(jump.block, anchor: .top)
                }
        }
    }
}
