import SwiftUI
import UIKit

/// Harbor's ordered chips and search grid, with the same 44-point actions on touch.
struct HarborLanguagesPicker: View {
    @Binding var value: String
    let identifier: String
    @State private var expanded = false
    @State private var query = ""

    private var selected: [String] { SubtitleLanguages.preferredCodes(value) }
    private var matches: [String] {
        let selectedCodes = Set(selected)
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return SubtitleLanguages.allCodes.filter {
            !selectedCodes.contains($0) && (search.isEmpty || SubtitleLanguages.preferenceName($0).localizedStandardContains(search))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LanguageChipLayout {
                ForEach(Array(selected.enumerated()), id: \.element) { index, code in
                    chip(code, index: index)
                }
                Button { expanded.toggle() } label: {
                    HStack(spacing: 8) {
                        icon(expanded ? "desktop-check" : "desktop-plus", size: 16)
                        Text(DesktopInterfaceText.value(expanded ? "Done" : "Add language"))
                    }.font(HarborTheme.font(14, weight: .semibold)).padding(.horizontal, 14)
                        .frame(minHeight: 44).background(HarborTheme.surface, in: .rect(cornerRadius: 8))
                }.accessibilityIdentifier(identifier + "-toggle")
            }
            if selected.isEmpty && !expanded {
                Text(DesktopInterfaceText.value("No preferred languages selected."))
                    .font(HarborTheme.font(15)).foregroundStyle(.secondary)
            }
            if expanded {
                searchGrid
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(DesktopInterfaceText.value("Language preference order"))
            .accessibilityValue(selected.joined(separator: ","))
            .accessibilityIdentifier(identifier)
    }

    private func chip(_ code: String, index: Int) -> some View {
        HStack(spacing: 8) {
            Text(String(index + 1)).font(HarborTheme.font(13)).monospacedDigit().foregroundStyle(.secondary)
            HarborLanguageFlag(code: code)
            Text(SubtitleLanguages.preferenceName(code)).font(HarborTheme.font(15))
                .fixedSize(horizontal: false, vertical: true)
            if index > 0 {
                Button {
                    var next = selected; next.swapAt(index, index - 1)
                    value = next.joined(separator: ",")
                } label: {
                    icon("music-arrow-down", size: 15).rotationEffect(.degrees(90)).frame(width: 44, height: 44)
                }.accessibilityLabel(label("Move {language} earlier", code: code))
                    .accessibilityIdentifier(identifier + "-earlier-" + code)
            }
            Button { value = selected.filter { $0 != code }.joined(separator: ",") } label: {
                icon("music-close", size: 15).frame(width: 44, height: 44)
            }.accessibilityLabel(label("Remove {language}", code: code))
                .accessibilityIdentifier(identifier + "-remove-" + code)
        }.padding(.leading, 12).frame(minHeight: 44)
            .background(HarborTheme.surface, in: .rect(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).stroke(HarborTheme.ink.opacity(0.06), lineWidth: 1) }
            .accessibilityElement(children: .contain)
            .accessibilityValue(String(index + 1))
            .accessibilityIdentifier(identifier + "-selected-" + code)
    }

    private var searchGrid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                icon("nav-search", size: 18).foregroundStyle(.secondary)
                TextField(DesktopInterfaceText.value("Search languages"), text: $query)
                    .font(HarborTheme.font(15)).autocorrectionDisabled().textInputAutocapitalization(.never)
                    .accessibilityIdentifier(identifier + "-search")
            }.padding(.horizontal, 16).frame(minHeight: 48)
            Divider().overlay(HarborTheme.ink.opacity(0.06))
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 4) {
                    ForEach(matches, id: \.self) { code in
                        Button {
                            value = (selected + [code]).joined(separator: ","); query = ""
                        } label: {
                            HStack(spacing: 10) {
                                HarborLanguageFlag(code: code)
                                Text(SubtitleLanguages.preferenceName(code)).font(HarborTheme.font(15))
                                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }.padding(.horizontal, 10).padding(.vertical, 6)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }.accessibilityLabel(label("Add {language}", code: code))
                            .accessibilityIdentifier(identifier + "-add-" + code)
                    }
                }.padding(8)
                if matches.isEmpty {
                    Text(DesktopInterfaceText.value(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "All languages have been added." : "No language matches that search."))
                        .font(HarborTheme.font(15)).foregroundStyle(.secondary).padding(16)
                }
            }.frame(height: 240)
        }.background(HarborTheme.surface, in: .rect(cornerRadius: 10))
            .clipShape(.rect(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).stroke(HarborTheme.ink.opacity(0.06), lineWidth: 1) }
    }

    private func icon(_ name: String, size: CGFloat) -> some View {
        Image(name).resizable().scaledToFit().frame(width: size, height: size).accessibilityHidden(true)
    }
    private func label(_ original: String, code: String) -> String {
        DesktopInterfaceText.value(original).replacingOccurrences(of: "{language}", with: SubtitleLanguages.preferenceName(code))
    }
}

private struct LanguageChipLayout: Layout {
    var spacing: CGFloat = 8
    private func positions(width: CGFloat, subviews: Subviews) -> [(CGPoint, CGSize)] {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        return subviews.map { view in
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > width {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            let point = CGPoint(x: x, y: y)
            x += size.width + spacing; rowHeight = max(rowHeight, size.height)
            return (point, size)
        }
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let layout = positions(width: width, subviews: subviews)
        return CGSize(width: width, height: layout.map { $0.0.y + $0.1.height }.max() ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (view, item) in zip(subviews, positions(width: bounds.width, subviews: subviews)) {
            view.place(at: CGPoint(x: bounds.minX + item.0.x, y: bounds.minY + item.0.y), anchor: .topLeading, proposal: ProposedViewSize(item.1))
        }
    }
}

struct HarborLanguageFlag: View {
    let code: String
    var body: some View {
        if UIImage(named: "language-flag-" + code) != nil {
            ZStack {
                if code == "pt-br" {
                    Image("language-flag-pt").resizable().scaledToFill().clipShape(FlagHalf(upper: false))
                    Image("language-flag-pt-br").resizable().scaledToFill().clipShape(FlagHalf(upper: true))
                    Path { $0.move(to: .zero); $0.addLine(to: CGPoint(x: 24, y: 16)) }.stroke(.white.opacity(0.55), lineWidth: 1)
                } else {
                    Image("language-flag-" + code).resizable().scaledToFill()
                }
            }.frame(width: 24, height: 16).clipShape(.rect(cornerRadius: 2))
                .overlay { RoundedRectangle(cornerRadius: 2).stroke(.white.opacity(0.06), lineWidth: 1) }
                .shadow(color: .black.opacity(0.4), radius: 1, y: 1).accessibilityHidden(true)
        }
    }
}

private struct FlagHalf: Shape {
    let upper: Bool
    func path(in rect: CGRect) -> Path {
        Path {
            $0.move(to: .zero)
            $0.addLine(to: upper ? CGPoint(x: rect.width, y: 0) : CGPoint(x: 0, y: rect.height))
            $0.addLine(to: CGPoint(x: rect.width, y: rect.height))
            $0.closeSubpath()
        }
    }
}
