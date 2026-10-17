import SwiftUI

struct AppWalkthroughView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("uiLanguage") private var language = "es"
    @State private var step = 0
    private let steps: [(title: String, message: String, icon: String)] = [
        ("Welcome to Harbor", "Choose your language. Your accounts and sources can be configured from your profile and Addons.", "harbor-mark"),
        ("Make it yours", "Use the navigation menu to open each section. Personalize the sidebar, home rows, colors and playback from Settings.", "nav-settings"),
        ("Read on iPhone and iPad", "In eBook, search Gutenberg or import EPUB and PDF files. In Manga, import PDF, CBZ, ZIP or image folders, or connect your Suwayomi server.", "nav-ebook"),
        ("Keep watching", "Resume from Continue watching. During playback, choose sources, audio and subtitles, synchronize an external subtitle or skip an intro when timing is available.", "nav-movies")
    ]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    HarborBrand(size: 42).padding(.top, 20)
                    HStack(spacing: 8) {
                        ForEach(steps.indices, id: \.self) { index in
                            Capsule().fill(index == step ? HarborTheme.ink : HarborTheme.ink.opacity(0.25)).frame(width: index == step ? 30 : 8, height: 6)
                        }
                    }.accessibilityElement(children: .ignore).accessibilityLabel("\(step + 1) / \(steps.count)")
                    VStack(spacing: 22) {
                        Image(steps[step].icon).resizable().scaledToFit().frame(width: 68, height: 68).accessibilityHidden(true)
                        Text(DesktopInterfaceText.value(steps[step].title)).font(HarborTheme.font(28, weight: .semibold)).multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                        Text(DesktopInterfaceText.value(steps[step].message)).font(HarborTheme.font(16)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.id(step).transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 12)))
                    if step == 0 {
                        HarborSettingsChoice(DesktopInterfaceText.value("Language"), selection: $language, choices: InterfaceLanguage.all.map { ($0.nativeLabel, $0.code) }, localizeChoices: false, identifier: "guide-language")
                    }
                    HStack(spacing: 16) {
                        if step > 0 { Button(DesktopInterfaceText.value("Back")) { changeStep(-1) }.buttonStyle(HarborAccountButtonStyle()).accessibilityIdentifier("guide-back") }
                        Button(DesktopInterfaceText.value(step == steps.count - 1 ? "Done" : "Next")) {
                            if step == steps.count - 1 { AppGuidePreferences.shared.finish() } else { changeStep(1) }
                        }.buttonStyle(HarborAccountButtonStyle()).accessibilityIdentifier("guide-next")
                    }.padding(.top, 8)
                }.padding(24).frame(maxWidth: 650).frame(maxWidth: .infinity)
            }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(DesktopInterfaceText.value("Skip")) { AppGuidePreferences.shared.finish() }.accessibilityIdentifier("guide-skip") } }
                .navigationTitle(DesktopInterfaceText.value("Onboarding")).navigationBarTitleDisplayMode(.inline)
        }.tint(HarborTheme.accent).preferredColorScheme(.dark)
            .environment(\.locale, Locale(identifier: InterfaceLanguage.resolve(language)))
            .environment(\.layoutDirection, InterfaceLanguage.resolve(language) == "ar" ? .rightToLeft : .leftToRight)
            .accessibilityIdentifier("app-walkthrough")
    }
    private func changeStep(_ amount: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { step = min(steps.count - 1, max(0, step + amount)) }
    }
}

struct AppHintView: View {
    let hint: AppHint
    let text: String
    var body: some View {
        if AppGuidePreferences.shared.isVisible(hint) {
            HStack(alignment: .top, spacing: 8) {
                Text(DesktopInterfaceText.value(text)).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                Button { AppGuidePreferences.shared.dismiss(hint) } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel(DesktopInterfaceText.value("Dismiss tip")).accessibilityIdentifier("hint-dismiss-" + hint.rawValue)
            }.accessibilityIdentifier("hint-" + hint.rawValue)
        }
    }
}
