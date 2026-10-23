import CoreText
import SwiftUI
import UIKit

@MainActor enum EBookAnnotationStyle {
    static func color(_ raw: String, alpha: Double = 1) -> UIColor {
        let value = UInt32(raw.dropFirst(), radix: 16) ?? 0
        return UIColor(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: CGFloat(min(1, max(0, alpha))))
    }
    static func attributed(_ text: String, paint: [EBookAnnotationPaint], font: CTFont, ink: UIColor, lineSpacing: Double, rtl: Bool, brightness: Double) -> NSAttributedString {
        let style = NSMutableParagraphStyle(); style.lineSpacing = lineSpacing; style.alignment = rtl ? .right : .left; style.baseWritingDirection = rtl ? .rightToLeft : .leftToRight
        let value = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: ink, .paragraphStyle: style])
        for run in paint where run.range.location >= 0 && run.range.location <= value.length && run.range.length <= value.length - run.range.location {
            let background = ReadingBrightness.color(color(run.color, alpha: run.density / 100).cgColor, percent: brightness)
            value.addAttribute(.backgroundColor, value: UIColor(cgColor: background), range: run.range)
        }
        return value
    }
}

struct EBookAnnotatedPassage: UIViewRepresentable {
    let text: String
    let paint: [EBookAnnotationPaint]
    let font: CTFont
    let ink: UIColor
    let spacing: Double
    let rtl: Bool
    let brightness: Double
    var semantic: String? = nil
    let selected: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UILabel {
        let label = UILabel(); label.numberOfLines = 0; label.lineBreakMode = .byWordWrapping; label.backgroundColor = .clear
        label.isUserInteractionEnabled = true; label.accessibilityIdentifier = "ebook-reader-text"
        label.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:))))
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }
    func updateUIView(_ label: UILabel, context: Context) {
        context.coordinator.parent = self
        label.attributedText = EBookAnnotationStyle.attributed(text, paint: paint, font: font, ink: ink, lineSpacing: spacing, rtl: rtl, brightness: brightness)
        label.accessibilityLabel = text
        label.accessibilityValue = semantic
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        uiView.preferredMaxLayoutWidth = width
        let measured = uiView.sizeThatFits(.init(width: width, height: .greatestFiniteMagnitude))
        return .init(width: width, height: ceil(measured.height))
    }
    @MainActor final class Coordinator: NSObject {
        var parent: EBookAnnotatedPassage
        init(_ parent: EBookAnnotatedPassage) { self.parent = parent }
        @objc func tap(_ gesture: UITapGestureRecognizer) {
            guard let label = gesture.view as? UILabel, let text = label.attributedText else { return }
            let storage = NSTextStorage(attributedString: text), manager = NSLayoutManager()
            let container = NSTextContainer(size: label.bounds.size); container.lineFragmentPadding = 0; container.lineBreakMode = .byWordWrapping
            manager.addTextContainer(container); storage.addLayoutManager(manager)
            let point = gesture.location(in: label)
            let glyph = manager.glyphIndex(for: point, in: container)
            guard glyph < manager.numberOfGlyphs, manager.boundingRect(forGlyphRange: .init(location: glyph, length: 1), in: container).insetBy(dx: -3, dy: -3).contains(point) else { return }
            let index = manager.characterIndexForGlyph(at: glyph)
            if let run = parent.paint.first(where: { NSLocationInRange(index, $0.range) }) { parent.selected(run.id) }
        }
    }
}

struct EBookAnnotationSelectionView: View {
    let document: EBookAnnotationDocument
    let busy: Bool
    let failure: String?
    let selected: (EBookAnnotationSelection, String) -> Void
    @State private var range: NSRange
    @Environment(\.dismiss) private var dismiss
    init(document: EBookAnnotationDocument, block: Int, busy: Bool, failure: String?, selected: @escaping (EBookAnnotationSelection, String) -> Void) {
        self.document = document; self.busy = busy; self.failure = failure; self.selected = selected
        _range = State(initialValue: document.paragraphs.first(where: { $0.block == block })?.range ?? .init(location: 0, length: 0))
    }
    private func text(_ value: String) -> String { DesktopInterfaceText.value(value) }
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(text("Select a passage to add a highlight, note, or reference.")).font(.caption).foregroundStyle(.secondary).padding()
                NativeBookSelection(text: document.text, selection: $range) { range, action in commit(range, action) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let failure { Text(failure).foregroundStyle(.orange).padding() }
                HStack(spacing: 16) {
                    Menu {
                        ForEach(EBookAnnotation.inks, id: \.self) { ink in Button(DesktopInterfaceText.value("Use {color} ink", variables: ["color": ink])) { commit(range, ink) }.accessibilityIdentifier("ebook-note-quick-" + ink) }
                    } label: { Label(text("Highlight"), systemImage: "highlighter") }.accessibilityIdentifier("ebook-note-highlight-action")
                    Button(text("Note")) { commit(range, "note") }.accessibilityIdentifier("ebook-note-create-action")
                    Button(text("Reference")) { commit(range, "reference") }.accessibilityIdentifier("ebook-note-reference-action")
                }.font(.subheadline).frame(maxWidth: .infinity, minHeight: 48).padding(.horizontal).padding(.bottom, 8)
                    .disabled(busy || document.selection(range) == nil)
            }.navigationTitle(text("Notes & highlights")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(text("Close")) { dismiss() }.accessibilityIdentifier("ebook-note-selection-close") } }
        }
    }
    private func commit(_ range: NSRange, _ action: String) { guard !busy, let value = document.selection(range) else { return }; selected(value, action) }
}

struct NativeBookSelection: UIViewRepresentable {
    let text: String
    @Binding var selection: NSRange
    let chosen: (NSRange, String) -> Void
    @Environment(\.layoutDirection) private var direction
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView(); view.isEditable = false; view.isSelectable = true; view.backgroundColor = .clear
        let descriptor = UIFont.systemFont(ofSize: 19).fontDescriptor.withDesign(.serif) ?? UIFont.systemFont(ofSize: 19).fontDescriptor
        let style = NSMutableParagraphStyle(); style.alignment = direction == .rightToLeft ? .right : .left; style.baseWritingDirection = direction == .rightToLeft ? .rightToLeft : .leftToRight
        view.attributedText = NSAttributedString(string: text, attributes: [.font: UIFont(descriptor: descriptor, size: 19), .foregroundColor: UIColor.label, .paragraphStyle: style])
        view.textContainerInset = .init(top: 16, left: 20, bottom: 24, right: 20)
        view.selectedRange = selection; view.delegate = context.coordinator
        view.accessibilityIdentifier = "ebook-note-selection-text"
        let initial = selection
        DispatchQueue.main.async { view.becomeFirstResponder(); view.selectedRange = initial; view.scrollRangeToVisible(initial) }
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) { context.coordinator.parent = self }
    @MainActor final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NativeBookSelection
        init(_ parent: NativeBookSelection) { self.parent = parent }
        func textViewDidChangeSelection(_ textView: UITextView) { parent.selection = textView.selectedRange }
        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            let actions = [("Highlight", EBookAnnotation.inks[0]), ("Note", "note"), ("Reference", "reference")].map { title, action in
                UIAction(title: DesktopInterfaceText.value(title)) { [weak self] _ in self?.parent.chosen(range, action) }
            }
            return UIMenu(children: suggestedActions + [UIMenu(options: .displayInline, children: actions)])
        }
    }
}
