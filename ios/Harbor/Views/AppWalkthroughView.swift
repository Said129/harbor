import SwiftUI

struct AppWalkthroughView: View {
    let app: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("uiLanguage") private var language = "es"
    @State private var step = OnboardingStep.splash
    @State private var picks = OnboardingTastePicks()
    @State private var taste: [Media]?
    @State private var tasteError: String?
    @State private var editingKey = false
    @State private var closing = false
    private var owner: String { app.personalOwner }
    private var tasteSignature: String { step == .taste ? owner + "|" + EBookShelf.hash(MetadataPreferences.shared.tmdbKey) : "" }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if step == .splash {
                    OnboardingSplash(app: app) { changeStep(.language) }.frame(maxHeight: 528)
                } else {
                    ScrollView {
                        content.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .contain).accessibilityIdentifier("guide-stage-" + step.rawValue)
                            .id(step).transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 12)))
                    }
                    .scrollDismissesKeyboard(.interactively).accessibilityIdentifier("guide-content")
                    footer
                }
            }.frame(maxWidth: step == .taste ? 640 : 580, maxHeight: step == .splash ? 528 : 720)
                .background(HarborTheme.surface.opacity(0.7), in: .rect(cornerRadius: 20))
                .overlay { RoundedRectangle(cornerRadius: 20).stroke(HarborTheme.ink.opacity(0.08), lineWidth: 1).allowsHitTesting(false) }
                .padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(HarborTheme.background).foregroundStyle(HarborTheme.ink)
                .scaleEffect(closing && !reduceMotion ? 0.97 : 1).opacity(closing ? 0 : 1)
                .toolbar {
                    if step != .splash {
                        ToolbarItem(placement: .cancellationAction) {
                            Button { finish() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                                .accessibilityLabel(DesktopInterfaceText.value("Skip setup")).accessibilityIdentifier("guide-skip")
                        }
                    }
                }.navigationTitle(DesktopInterfaceText.value("Onboarding")).navigationBarTitleDisplayMode(.inline)
        }.tint(HarborTheme.accent).preferredColorScheme(.dark)
            .environment(\.locale, Locale(identifier: InterfaceLanguage.resolve(language)))
            .environment(\.layoutDirection, InterfaceLanguage.resolve(language) == "ar" ? .rightToLeft : .leftToRight)
            .accessibilityIdentifier("app-walkthrough")
            .sheet(isPresented: $editingKey) { MetadataKeyEditor(preferences: .shared) }
            .task(id: tasteSignature) {
                guard step == .taste else { return }
                let expectedOwner = owner
                taste = nil; tasteError = nil
                do {
                    let titles = try await OnboardingContent().taste(configuration: MetadataPreferences.shared.configuration(), service: app.service)
                    try Task.checkCancellation()
                    guard owner == expectedOwner else { return }
                    taste = titles
                } catch is CancellationError {} catch { if owner == expectedOwner { taste = []; tasteError = safeMessage(error) } }
            }
            .onChange(of: owner) { _, _ in picks.reset(); taste = nil; tasteError = nil }
            .task(id: closing) {
                guard closing else { return }
                if !reduceMotion { do { try await Task.sleep(for: .milliseconds(320)) } catch { return } }
                AppGuidePreferences.shared.finish()
            }
    }
    @ViewBuilder private var content: some View {
        switch step {
        case .splash: EmptyView()
        case .language: OnboardingLanguageStep(language: $language)
        case .welcome: OnboardingWelcomeStep()
        case .layout:
            VStack(alignment: .leading, spacing: 22) {
                OnboardingHeading("Pick a home layout", message: "You can switch later in Settings under Library & metadata.")
                HomeStylePicker(selection: Binding(get: { InterfacePreferences.shared.homeMode }, set: { InterfacePreferences.shared.homeMode = $0 }))
            }
        case .tmdb: OnboardingMetadataStep { editingKey = true }
        case .stremio: OnboardingAccountStep(app: app)
        case .streaming:
            VStack(alignment: .leading, spacing: 22) {
                OnboardingHeading("Pick what you actually use", message: "Harbor pulls the most popular titles each service has right now. Toggle off anything you don't subscribe to.", eyebrow: "Step 3 · Streaming")
                StreamingServicePicker(preferences: .forOwner(app.settingsOwner))
            }
        case .subtitles:
            VStack(alignment: .leading, spacing: 22) {
                OnboardingHeading("Pick your subtitle languages", message: "When playback starts, Harbor finds and loads a subtitle in one of these languages automatically. The first available match wins, so put your main language first.", eyebrow: "Step 4 · Subtitles")
                HarborLanguagesPicker(value: Binding(get: { PlaybackPreferences.shared.options.subtitleLanguage }, set: { PlaybackPreferences.shared.options.subtitleLanguage = $0 }), identifier: "guide-subtitle-languages")
            }
        case .taste:
            OnboardingTasteStep(items: taste, picks: $picks)
            if let tasteError { Text(DesktopInterfaceText.value(tasteError)).font(.caption).foregroundStyle(.orange) }
        case .done: OnboardingDoneStep(owner: app.settingsOwner)
        }
    }
    private var footer: some View {
        VStack(spacing: 12) {
            ViewThatFits(in: .horizontal) {
                progressDots
                ScrollView(.horizontal) { progressDots }.scrollIndicators(.hidden)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { actions }
                VStack(spacing: 8) { actions }
            }
        }.padding(.horizontal, 16).padding(.bottom, 16)
            .background(HarborTheme.background.opacity(0.5)).disabled(closing)
    }
    private var progressDots: some View {
        HStack(spacing: 7) {
            ForEach(OnboardingStep.allCases.filter { $0 != .splash }) { item in
                Button { changeStep(item) } label: {
                    Capsule().fill(item == step ? HarborTheme.ink : HarborTheme.ink.opacity(0.22))
                        .frame(width: item == step ? 24 : 6, height: 6).frame(minWidth: 26, minHeight: 44)
                }.buttonStyle(.plain).accessibilityLabel("\(item.index) / 9")
                    .accessibilityAddTraits(item == step ? [.isSelected] : []).accessibilityIdentifier("guide-step-" + item.rawValue)
            }
        }
    }
    @ViewBuilder private var actions: some View {
        if step.canSkip {
            Button(DesktopInterfaceText.value("Skip for now")) { changeStep(step.next) }.frame(minHeight: 44).font(HarborTheme.font(13))
                .foregroundStyle(.secondary).accessibilityIdentifier("guide-skip-step")
        }
        if step.index > 1 && step != .done {
            Button(DesktopInterfaceText.value("Back")) { changeStep(step.previous) }.buttonStyle(HarborAccountButtonStyle()).accessibilityIdentifier("guide-back")
        }
        Button(DesktopInterfaceText.value(step == .done ? "Enter Harbor" : step == .welcome ? "Get Started" : "Continue")) { advance() }
            .buttonStyle(HarborAccountButtonStyle(primary: true)).accessibilityIdentifier("guide-next")
    }
    private func advance() {
        if step == .done { finish(); return }
        if step == .taste {
            let preferences = DiscoveryPreferences(owner: owner)
            guard preferences.seedTaste(picks.values) else { tasteError = preferences.error ?? "Could not save your choices. Try again."; return }
        }
        changeStep(step.next)
    }
    private func changeStep(_ next: OnboardingStep) {
        withAnimation(reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.42)) { step = next }
    }
    private func finish() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.32)) { closing = true }
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
