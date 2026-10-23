import SwiftUI

struct EBookPassageSearchView: View {
    let paragraphs: [EBookSearchParagraph]
    let currentBlock: Int
    @State private var program = EBookSearchProgram()
    @Binding var query: String
    @Binding var revealFuture: Bool
    let selected: (Int) -> Void
    @State private var outcome = EBookPassageSearch.empty
    @State private var pending = false
    @State private var failure: String?
    @State private var retry = UUID()
    @Environment(\.dismiss) private var dismiss
    private struct Request: Hashable { let query: String; let reveal: Bool; let retry: UUID }
    private var request: Request { .init(query: query, reveal: revealFuture, retry: retry) }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(DesktopInterfaceText.value("Diacritic-insensitive · results ahead stay sealed")).font(.caption).foregroundStyle(.secondary)
                }
                if pending { ProgressView() }
                if let failure {
                    Text(failure).font(.caption).foregroundStyle(.secondary)
                    Button(DesktopInterfaceText.value("Retry")) { retry = UUID() }
                }
                ForEach(outcome.shown) { result in
                    if paragraphs.indices.contains(result.index) {
                        Button {
                            selected(paragraphs[result.index].block); dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(DesktopInterfaceText.value("Passage {passage}", variables: ["passage": String(result.index + 1)])).font(.caption).foregroundStyle(.secondary)
                                Text(result.preview).font(.body).foregroundStyle(.primary)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                        }.accessibilityIdentifier("ebook-passage-result-" + String(result.index))
                    }
                }
                if outcome.hidden > 0 {
                    Button { revealFuture = true } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(DesktopInterfaceText.value(outcome.hidden == 1 ? "{count} match ahead" : "{count} matches ahead", variables: ["count": String(outcome.hidden)])).fontWeight(.semibold)
                            Text(DesktopInterfaceText.value("Show them anyway")).font(.caption)
                        }.padding(.vertical, 6)
                    }.accessibilityIdentifier("ebook-passage-reveal")
                }
            }
            .searchable(text: $query, prompt: DesktopInterfaceText.value("Find a word or passage"))
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(DesktopInterfaceText.value("Search chapter"))
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(DesktopInterfaceText.value("Close panel")) { dismiss() }.accessibilityIdentifier("ebook-passage-close") } }
        }
        .onChange(of: query) { _, _ in revealFuture = false }
        .task(id: request) {
            let expected = request
            pending = true; failure = nil; outcome = .empty
            defer { if expected == request { pending = false } }
            do {
                try await Task.sleep(for: .milliseconds(150))
                let current = paragraphs.lastIndex(where: { $0.block <= currentBlock }) ?? 0
                let result = try await program.search(paragraphs.map(\.text), query: expected.query, current: current, revealFuture: expected.reveal)
                try Task.checkCancellation(); guard request == expected else { return }; outcome = result
            } catch { if !Task.isCancelled && expected == request { failure = safeMessage(error) } }
        }
    }
}
