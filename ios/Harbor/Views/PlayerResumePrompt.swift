import SwiftUI

struct PlayerResumePrompt: View {
    let title: String
    let resumeMs: Double
    let duration: Double
    let busy: Bool
    let onResume: () -> Void
    let onStartOver: () -> Void
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var seconds: Double { resumeMs.isFinite ? max(0, resumeMs / 1000) : 0 }
    private var hasDuration: Bool { duration.isFinite && duration > 0 }
    private var percent: Int { hasDuration ? Int(min(100, max(0, (seconds / duration * 100).rounded()))) : 0 }
    private var watched: String {
        DesktopInterfaceText.value("{watched} of {total} watched ({pct}%).")
            .replacingOccurrences(of: "{watched}", with: Self.formatTime(seconds))
            .replacingOccurrences(of: "{total}", with: Self.formatTime(duration))
            .replacingOccurrences(of: "{pct}", with: String(percent))
    }
    private var resumeTitle: String {
        DesktopInterfaceText.value("Resume from {time}").replacingOccurrences(of: "{time}", with: Self.formatTime(seconds))
    }
    var body: some View {
        ZStack {
            LinearGradient(stops: [.init(color: .black.opacity(0.9), location: 0), .init(color: .black.opacity(0.55), location: 0.5), .init(color: .clear, location: 1)], startPoint: .bottom, endPoint: .top)
                .ignoresSafeArea().contentShape(Rectangle())
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ViewThatFits(in: .vertical) {
                    card
                    ScrollView { card }.scrollBounceBehavior(.basedOnSize)
                }.frame(maxWidth: 576)
            }.padding(.horizontal, 16).padding(.top, 60).padding(.bottom, verticalSizeClass == .compact ? 16 : 64)
        }.accessibilityIdentifier("player-resume-prompt")
    }
    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(DesktopInterfaceText.value("Pick up where you left off").uppercased())
                .font(HarborTheme.font(11, weight: .semibold)).tracking(3.52)
                .foregroundStyle(ThemePreferences.shared.color("ink-subtle"))
                .fixedSize(horizontal: false, vertical: true)
            Text(title).font(HarborTheme.displayFont(24)).lineLimit(2)
                .foregroundStyle(HarborTheme.ink).padding(.top, 12).accessibilityAddTraits(.isHeader)
            if hasDuration {
                Text(watched).font(HarborTheme.font(13.5)).foregroundStyle(ThemePreferences.shared.color("ink-muted"))
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 8).accessibilityIdentifier("player-resume-progress")
                GeometryReader { geometry in
                    Capsule().fill(ThemePreferences.shared.color("elevated"))
                        .overlay(alignment: .leading) { Capsule().fill(HarborTheme.accent).frame(width: geometry.size.width * CGFloat(percent) / 100) }
                }.frame(height: 4).padding(.top, 20).accessibilityHidden(true)
            }
            let buttons = verticalSizeClass == .compact ? AnyLayout(HStackLayout(spacing: 10)) : AnyLayout(VStackLayout(spacing: 10))
            buttons {
                Button(action: onResume) {
                    HStack(spacing: 10) {
                        Image("ui-play-filled").resizable().scaledToFit().frame(width: 18, height: 18).scaleEffect(0.82).accessibilityHidden(true)
                        Text(resumeTitle).font(HarborTheme.font(15, weight: .semibold))
                    }.padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(HarborTheme.background).background(HarborTheme.accent, in: .capsule)
                        .shadow(color: HarborTheme.accent.opacity(0.3), radius: 11, y: 8)
                }.buttonStyle(.plain).disabled(busy).accessibilityIdentifier("player-resume-continue")
                Button(action: onStartOver) {
                    HStack(spacing: 10) {
                        Image("resume-start-over").resizable().scaledToFit().frame(width: 16, height: 16).accessibilityHidden(true)
                        Text(DesktopInterfaceText.value("Start Over")).font(HarborTheme.font(14, weight: .semibold))
                    }.padding(.horizontal, 24).frame(maxWidth: .infinity, minHeight: 48).foregroundStyle(HarborTheme.ink)
                        .background(ThemePreferences.shared.color("elevated"), in: .capsule)
                        .overlay { Capsule().stroke(ThemePreferences.shared.color("edge-soft"), lineWidth: 1) }
                }.buttonStyle(.plain).disabled(busy).accessibilityIdentifier("player-resume-start-over")
            }.padding(.top, 24)
        }.padding(28).background(HarborTheme.surface, in: .rect(cornerRadius: 24))
            .overlay { RoundedRectangle(cornerRadius: 24).stroke(ThemePreferences.shared.color("edge-soft"), lineWidth: 1) }
            .shadow(color: .black.opacity(0.85), radius: 40, y: 30)
    }
    private static func formatTime(_ value: Double) -> String {
        guard value.isFinite, value >= 0, value < Double(Int.max) else { return "0:00" }
        let seconds = Int(value), hours = seconds / 3600, minutes = seconds / 60 % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds % 60) : String(format: "%d:%02d", minutes, seconds % 60)
    }
}
