import SwiftUI

struct OnboardingHeading: View {
    let title: String
    let message: String
    let eyebrow: String?
    init(_ title: String, message: String, eyebrow: String? = nil) { self.title = title; self.message = message; self.eyebrow = eyebrow }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let eyebrow { Text(DesktopInterfaceText.value(eyebrow).uppercased()).font(HarborTheme.font(12.5, weight: .medium)).tracking(1.8).foregroundStyle(.secondary) }
            Text(DesktopInterfaceText.value(title)).font(HarborTheme.displayFont(32)).accessibilityAddTraits(.isHeader).accessibilityIdentifier("guide-heading")
            Text(DesktopInterfaceText.value(message)).font(HarborTheme.font(15)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct OnboardingLanguageStep: View {
    @Binding var language: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var picked = false
    @State private var drift = 0
    private var greeting: InterfaceLanguage? {
        let choices = InterfaceLanguage.all
        return reduceMotion || picked ? choices.first { $0.code == language } : choices.isEmpty ? nil : choices[drift % choices.count]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ZStack(alignment: .leading) {
                ForEach(InterfaceLanguage.all) { option in
                    Text(option.greeting ?? "Hello").font(HarborTheme.displayFont(38)).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.7).opacity(option.code == greeting?.code ? 1 : 0)
                        .environment(\.layoutDirection, option.rtl == true ? .rightToLeft : .leftToRight)
                }
            }.accessibilityHidden(true).animation(reduceMotion ? nil : .easeInOut(duration: 0.9), value: greeting?.code)
            OnboardingHeading("Pick your language", message: "Harbor's own menus and labels. Subtitle languages come later, and you can change both in Settings.")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                ForEach(InterfaceLanguage.all) { option in
                    let selected = language == option.code
                    Button { language = option.code; picked = true } label: {
                        HStack(alignment: .center, spacing: 10) {
                            Image(systemName: selected ? "largecircle.fill.circle" : "circle").font(.system(size: 19)).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.nativeLabel).font(HarborTheme.font(15, weight: .semibold))
                                    .environment(\.layoutDirection, option.rtl == true ? .rightToLeft : .leftToRight)
                                if let label = option.label { Text(DesktopInterfaceText.value(label)).font(HarborTheme.font(12.5)).foregroundStyle(.secondary) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(14).frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                            .background(selected ? HarborTheme.surface : HarborTheme.background.opacity(0.4), in: .rect(cornerRadius: 16))
                            .overlay { RoundedRectangle(cornerRadius: 16).stroke(selected ? HarborTheme.ink : HarborTheme.ink.opacity(0.08), lineWidth: 1) }
                    }.buttonStyle(.plain).foregroundStyle(HarborTheme.ink).accessibilityLabel(option.nativeLabel)
                        .accessibilityAddTraits(selected ? [.isSelected] : []).accessibilityIdentifier("guide-language-" + option.code)
                }
            }
        }.task(id: "\(picked)|\(reduceMotion)|\(scenePhase)") {
            guard !picked, !reduceMotion, scenePhase == .active else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                drift = (drift + 1) % max(InterfaceLanguage.all.count, 1)
            }
        }
    }
}

struct OnboardingWelcomeStep: View {
    private let features = [("Current", "Trending, in theaters, what's on every streamer."), ("Yours", "Your Stremio library + addons sync in untouched."), ("Quiet", "No telemetry, no servers, no bundled keys.")]
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HarborBrand(size: 44, tiltedO: true)
            Text(DesktopInterfaceText.value("A client for the Stremio protocol. Two minutes to set up; most of it optional. You stay in control of every key."))
                .font(HarborTheme.font(15.5)).foregroundStyle(.secondary).accessibilityIdentifier("guide-heading")
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 10) { ForEach(features, id: \.0) { feature in card(feature).frame(minWidth: 115) } }
                VStack(alignment: .leading, spacing: 10) { ForEach(features, id: \.0) { feature in card(feature) } }
            }
        }
    }
    private func card(_ feature: (String, String)) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(DesktopInterfaceText.value(feature.0).uppercased()).font(HarborTheme.font(12.5, weight: .semibold)).tracking(1.2)
            Text(DesktopInterfaceText.value(feature.1)).font(HarborTheme.font(12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(HarborTheme.background.opacity(0.6), in: .rect(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(HarborTheme.ink.opacity(0.08), lineWidth: 1) }
    }
}

struct OnboardingMetadataStep: View {
    let edit: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingHeading("Connect TMDB", message: "Free, two-minute signup. Unlocks Trending, In Theaters Now, Top Rated, and per-streaming catalogs (Netflix, Disney+, Hulu, …). Your key stays on this machine.", eyebrow: "Step 1 · Metadata")
            Link(DesktopInterfaceText.value("Get a free key at themoviedb.org"), destination: URL(string: "https://www.themoviedb.org/settings/api")!).frame(minHeight: 44)
            HStack(spacing: 14) {
                Image("metadata-tmdb").resizable().scaledToFit().frame(width: 32, height: 32).accessibilityHidden(true)
                Text(DesktopInterfaceText.value(MetadataPreferences.shared.tmdbKey.isEmpty ? "Not set" : "Saved")).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button(DesktopInterfaceText.value(MetadataPreferences.shared.tmdbKey.isEmpty ? "Add key" : "Manage"), action: edit)
                    .buttonStyle(HarborAccountButtonStyle()).accessibilityIdentifier("guide-metadata-key")
            }.padding(16).background(HarborTheme.background, in: .rect(cornerRadius: 12))
            if let error = MetadataPreferences.shared.error { Text(error).font(.caption).foregroundStyle(.orange) }
        }
    }
}

struct OnboardingAccountStep: View {
    let app: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingHeading("Bring in your library", message: "Sign in to mirror your Continue Watching, watchlist, and any addons you've already curated. Optional; Harbor works fully signed-out.", eyebrow: "Step 2 · Stremio")
            if let user = app.user {
                Label(user.displayName, systemImage: "checkmark.circle.fill").privacySensitive().padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading).background(HarborTheme.background, in: .rect(cornerRadius: 12))
            }
            NavigationLink { AccountView(app: app).toolbar(.visible, for: .navigationBar) } label: {
                Label { Text(DesktopInterfaceText.value(app.user == nil ? "Sign in" : "Manage")) } icon: {
                    Image("account-stremio").resizable().scaledToFit().frame(width: 24, height: 24).accessibilityHidden(true)
                }.frame(minHeight: 44)
            }.buttonStyle(HarborAccountButtonStyle()).accessibilityIdentifier("guide-stremio-account")
            Link(DesktopInterfaceText.value("Create account"), destination: URL(string: "https://www.stremio.com/register")!).frame(minHeight: 44)
        }
    }
}

struct OnboardingTasteStep: View {
    let items: [Media]?
    @Binding var picks: OnboardingTastePicks
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            OnboardingHeading("Pick a few you love", message: "Choose up to 5 movies or shows you already like. Harbor uses them to tune your featured picks and recommendations. Totally optional.")
            if let items {
                if items.isEmpty { Text(DesktopInterfaceText.value("No results")).font(.caption).foregroundStyle(.secondary) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 10)], spacing: 10) {
                    ForEach(items, id: \.id) { media in
                        let selected = picks.values.contains { $0.id == media.id }
                        let atLimit = !selected && picks.values.count >= OnboardingTastePicks.maximum
                        Button { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { picks.toggle(media) } } label: {
                            ZStack {
                                Rectangle().fill(HarborTheme.surface)
                                Artwork(url: media.poster, maxPixels: 360)
                                Color.black.opacity(selected ? 0.45 : 0).allowsHitTesting(false)
                                Image("onboarding-thumbsup").resizable().scaledToFit().padding(22).shadow(radius: 5)
                                    .scaleEffect(selected ? 1 : 0.75).opacity(selected ? 1 : 0).allowsHitTesting(false).accessibilityHidden(true)
                            }.aspectRatio(2.0 / 3, contentMode: .fit)
                                .clipShape(.rect(cornerRadius: 12)).contentShape(.rect(cornerRadius: 12)).opacity(atLimit ? 0.4 : 1)
                        }.buttonStyle(OnboardingPosterButtonStyle()).disabled(atLimit).accessibilityLabel(media.name).accessibilityAddTraits(selected ? [.isSelected] : [])
                            .accessibilityIdentifier("guide-taste-" + media.id)
                    }
                }
            } else { HarborLoader().frame(maxWidth: .infinity).padding(24) }
        }
    }
}

private struct OnboardingPosterButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: configuration.isPressed)
    }
}

struct OnboardingDoneStep: View {
    let owner: String
    var body: some View {
        VStack(spacing: 24) {
            OnboardingDoneCheck().frame(width: 84, height: 84).accessibilityHidden(true)
            Text(DesktopInterfaceText.value("You're set.")).font(HarborTheme.displayFont(40)).accessibilityAddTraits(.isHeader).accessibilityIdentifier("guide-heading")
            Text(summary).font(HarborTheme.font(15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(.vertical, 24).frame(maxWidth: .infinity)
    }
    private var summary: String {
        if MetadataPreferences.shared.tmdbKey.isEmpty { return DesktopInterfaceText.value("Running on Cinemeta for now. Add a TMDB key from Settings whenever you're ready.") }
        let enabled = StreamingPreferences.forOwner(owner).enabled.count
        return DesktopInterfaceText.value("TMDB connected. {n} streaming {services} on. Welcome aboard.", variables: ["n": String(enabled), "services": DesktopInterfaceText.value(enabled == 1 ? "service" : "services")])
    }
}

private struct OnboardingDoneCheck: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    var body: some View {
        ZStack {
            Circle().trim(from: 0, to: appeared || reduceMotion ? 1 : 0).stroke(.green, style: StrokeStyle(lineWidth: 3, lineCap: .round)).padding(6).rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.72).delay(0.08), value: appeared)
            CheckStroke().trim(from: 0, to: appeared || reduceMotion ? 1 : 0).stroke(.green, style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.36).delay(0.48), value: appeared)
        }.scaleEffect(appeared || reduceMotion ? 1 : 0.6).opacity(appeared || reduceMotion ? 1 : 0)
            .animation(reduceMotion ? nil : .spring(duration: 0.54, bounce: 0.22), value: appeared).onAppear { appeared = true }
    }
    private struct CheckStroke: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.width * 27 / 84, y: rect.height * 43 / 84))
                path.addLine(to: CGPoint(x: rect.width * 37.5 / 84, y: rect.height * 53.5 / 84))
                path.addLine(to: CGPoint(x: rect.width * 57 / 84, y: rect.height * 33 / 84))
            }
        }
    }
}
