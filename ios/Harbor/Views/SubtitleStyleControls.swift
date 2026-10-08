import SwiftUI
import UIKit

struct SubtitleStylePreview: View {
    let options: PlaybackOptions
    private var alignment: Alignment {
        switch options.subtitleAlignment { case "left": .bottomLeading; case "right": .bottomTrailing; default: .bottom }
    }
    var body: some View {
        GeometryReader { geometry in
            let scale = max(geometry.size.width / 1440, geometry.size.height / 810)
            let imageWidth = 1920 * 0.773437 * scale
            let imageHeight = 1080 * 0.773611 * scale
            let previewSize = CGFloat((min(120, max(16, options.subtitleSize)) * 0.55).rounded())
            Image("subtitle-preview").resizable().frame(width: imageWidth, height: imageHeight)
                .position(x: (geometry.size.width - 1440 * scale + imageWidth) / 2, y: (geometry.size.height - 810 * scale + imageHeight) / 2)
                .accessibilityHidden(true)
            LinearGradient(colors: [.clear, HarborTheme.background.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                .overlay(alignment: alignment) {
                    SubtitlePreviewLabel(options: options, size: previewSize)
                        .padding(.vertical, options.subtitleStyle == "box" ? previewSize * 0.18 : 0)
                        .padding(.horizontal, options.subtitleStyle == "box" ? previewSize * 0.5 : 0)
                        .background(options.subtitleStyle == "box" ? Color(hex: options.subtitleBoxColor).opacity(options.boxOpacity) : .clear, in: .rect(cornerRadius: previewSize * 0.25))
                        .opacity(options.subtitleOpacity)
                        .padding(.horizontal, geometry.size.width * 0.06)
                        .padding(.bottom, geometry.size.height * min(100, max(0, 100 - options.subtitlePosition)) / 100)
                }
        }.frame(height: 224).clipShape(.rect(cornerRadius: 10)).accessibilityElement(children: .combine)
            .accessibilityLabel(DesktopInterfaceText.value("This is how your subtitles will look.")).accessibilityIdentifier("settings-subtitle-preview")
    }
}

private struct SubtitlePreviewLabel: UIViewRepresentable {
    let options: PlaybackOptions
    let size: CGFloat
    func makeUIView(context: Context) -> UILabel {
        let label = UILabel(); label.numberOfLines = 0
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }
    func updateUIView(_ label: UILabel, context: Context) {
        var font = UIFont(name: SubtitleStyleFont(rawValue: options.subtitleFont)?.family ?? "Inter-Regular", size: size) ?? .systemFont(ofSize: size)
        if options.subtitleBold, let descriptor = font.fontDescriptor.withSymbolicTraits(.traitBold) { font = UIFont(descriptor: descriptor, size: size) }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineHeightMultiple = 1.2
        paragraph.alignment = options.subtitleAlignment == "left" ? .left : options.subtitleAlignment == "right" ? .right : .center
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(Color(hex: options.subtitleColor)), .paragraphStyle: paragraph, .kern: options.subtitleSpacing]
        if options.subtitleStyle == "outline" {
            attributes[.strokeColor] = UIColor(Color(hex: options.borderColor))
            attributes[.strokeWidth] = -max(1, options.borderSize) * 0.55 / Double(size) * 100
        } else if options.subtitleStyle == "shadow" {
            let shadow = NSShadow(); shadow.shadowColor = UIColor.black.withAlphaComponent(0.95)
            shadow.shadowOffset = CGSize(width: 0, height: 1); shadow.shadowBlurRadius = 2
            attributes[.shadow] = shadow
        }
        label.attributedText = NSAttributedString(string: DesktopInterfaceText.value("This is how your subtitles will look."), attributes: attributes)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        uiView.sizeThatFits(CGSize(width: proposal.width ?? uiView.intrinsicContentSize.width, height: CGFloat.greatestFiniteMagnitude))
    }
}

enum SubtitleStyleFont: String, CaseIterable, Identifiable {
    case inter, system, rounded, serif, arabic
    var id: String { rawValue }
    var family: String {
        switch self {
        case .inter: "Inter-Regular"
        case .system: "HelveticaNeue"
        case .rounded: "Fredoka-Light"
        case .serif: "TimesNewRomanPSMT"
        case .arabic: "Vazirmatn-Regular"
        }
    }
    var title: String { DesktopInterfaceText.value(rawValue.prefix(1).uppercased() + String(rawValue.dropFirst())) }
}

struct SubtitleBackgroundChoices: View {
    @Binding var selection: String
    private let choices = [("shadow", "Drop shadow", "Soft halo around the text. Cleanest on most content."), ("outline", "Outline", "Hard stroke around each letter. High contrast."), ("box", "Black bar", "Rounded background panel behind the text. Most readable.")]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            ForEach(choices, id: \.0) { choice in
                Button { selection = choice.0 } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(DesktopInterfaceText.value(choice.1)).font(HarborTheme.font(14, weight: .semibold))
                        Text(DesktopInterfaceText.value(choice.2)).font(HarborTheme.font(12)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading).padding(12)
                        .background(HarborTheme.surface, in: .rect(cornerRadius: 10))
                        .overlay { RoundedRectangle(cornerRadius: 10).stroke(selection == choice.0 ? HarborTheme.accent : HarborTheme.ink.opacity(0.1), lineWidth: 1) }
                }.buttonStyle(.plain).accessibilityAddTraits(selection == choice.0 ? .isSelected : [])
                    .accessibilityIdentifier("subtitle-style-" + choice.0)
            }
        }
    }
}

struct SubtitleFontChoices: View {
    @Binding var selection: String
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            ForEach(SubtitleStyleFont.allCases) { font in
                Button { selection = font.rawValue } label: {
                    Text(font.title).font(.custom(font.family, size: 16.5).weight(.semibold)).frame(maxWidth: .infinity, minHeight: 56)
                        .background(HarborTheme.surface, in: .rect(cornerRadius: 10))
                        .overlay { RoundedRectangle(cornerRadius: 10).stroke(selection == font.rawValue ? HarborTheme.accent : HarborTheme.ink.opacity(0.1), lineWidth: 1) }
                }.buttonStyle(.plain).accessibilityAddTraits(selection == font.rawValue ? .isSelected : [])
            }
        }
    }
}

struct SubtitleColorField: View {
    let title: String
    @Binding var value: String
    let fallback: String
    private let colors = ["#FFFFFF", "#000000", "#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#5AC8FA", "#007AFF", "#AF52DE", "#FF2D92"]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(HarborTheme.font(14, weight: .semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44, maximum: 44), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(colors, id: \.self) { color in
                    Button { value = color } label: {
                        RoundedRectangle(cornerRadius: 10).fill(Color(hex: color)).frame(width: 44, height: 44)
                            .overlay { RoundedRectangle(cornerRadius: 10).stroke(value.uppercased() == color ? HarborTheme.ink : HarborTheme.ink.opacity(0.15), lineWidth: 2) }
                    }.buttonStyle(.plain).accessibilityLabel(color).accessibilityAddTraits(value.uppercased() == color ? .isSelected : [])
                }
            }
            HStack {
                ColorPicker(value.uppercased(), selection: Binding(get: { Color(hex: value) }, set: { value = $0.rgbHex }), supportsOpacity: false)
                    .frame(minHeight: 44)
                Button(DesktopInterfaceText.value("Reset")) { value = fallback }.frame(minHeight: 44)
                    .disabled(value.uppercased() == fallback.uppercased())
            }
        }
    }
}
