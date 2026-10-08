import SwiftUI

struct HarborHeroTitle: View {
    let media: Media
    var size: CGFloat = 32
    var height: CGFloat = 90
    @State private var logoLoaded = false
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Text(media.name).font(HarborTheme.displayFont(size)).lineLimit(3)
                .foregroundStyle(logoLoaded ? Color.clear : HarborTheme.ink).accessibilityAddTraits(.isHeader)
            if let logo = media.logo {
                Artwork(url: logo, fit: .fit, maxPixels: 800, showsPlaceholder: false, onImageAvailability: { logoLoaded = $0 })
                    .frame(maxWidth: 300).frame(height: height).accessibilityHidden(true)
            }
        }.frame(minHeight: height, alignment: .bottomLeading)
            .onChange(of: media.logo) { _, _ in logoLoaded = false }
    }
}

struct HarborAnimeHero: View {
    let metas: [Media]
    let sources: [String: String]
    let picks: PageRail?
    let app: AppModel
    let customization: PageCustomization
    @State private var selected = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var slides: [Media] { Array(metas.prefix(6)) }
    var body: some View {
        ZStack(alignment: .top) {
            if slides.indices.contains(selected) {
                let media = slides[selected]
                GeometryReader { bounds in
                    Artwork(url: media.background, fallback: media.poster, maxPixels: 1400)
                        .frame(width: bounds.size.width, height: bounds.size.height)
                        .overlay(LinearGradient(colors: [.black.opacity(0.18), HarborTheme.background.opacity(0.62), HarborTheme.background], startPoint: .top, endPoint: .bottom))
                }.accessibilityHidden(true).allowsHitTesting(false)
            }
            VStack(alignment: .leading, spacing: 16) {
                if !slides.isEmpty {
                    TabView(selection: $selected) {
                        ForEach(Array(slides.enumerated()), id: \.element.identity) { index, media in
                            HarborAnimeSlide(media: media, source: sources[media.id], app: app).tag(index)
                        }
                    }.tabViewStyle(.page(indexDisplayMode: .never)).frame(height: 435)
                    HarborHeroPips(count: slides.count, selected: selected) { index in withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.7)) { selected = index } }
                }
                if let picks {
                    CustomizedRails(rails: [picks], app: app, customization: customization)
                }
            }.padding(.bottom, 12)
        }.clipped().accessibilityIdentifier("anime-original-hero")
            .onChange(of: slides.map(\.identity)) { _, _ in if selected >= slides.count { selected = 0 } }
            .task(id: "\(scenePhase == .active)|\(reduceMotion)|\(selected)|\(slides.map(\.identity).joined())") {
                guard scenePhase == .active, !reduceMotion, slides.count > 1 else { return }
                do { try await Task.sleep(for: .seconds(14)); try Task.checkCancellation(); withAnimation(.easeInOut(duration: 0.7)) { selected = (selected + 1) % slides.count } } catch {}
            }
    }
}

private struct HarborAnimeSlide: View {
    let media: Media
    let source: String?
    let app: AppModel
    @State private var hint: String?
    @State private var hintRevision = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var saved: Bool { app.library.bookmarked(media) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer(minLength: 65)
            if let source {
                HStack(spacing: 7) { Image("desktop-trending-up").resizable().scaledToFit().frame(width: 16, height: 16).foregroundStyle(HarborTheme.accent); Text(DesktopInterfaceText.value("Trending on {source}").replacingOccurrences(of: "{source}", with: source)).font(HarborTheme.font(11, weight: .semibold)).textCase(.uppercase).tracking(1) }
            }
            HarborHeroTitle(media: media, size: 32, height: 100)
            HStack(spacing: 8) {
                if let year = media.releaseInfo { Text(year) }
                ForEach(Array((media.genres ?? []).prefix(2)), id: \.self) { genre in Text("·").accessibilityHidden(true); Text(genre) }
            }.font(HarborTheme.font(12)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
            if let description = media.description { Text(description).font(HarborTheme.font(14)).foregroundStyle(.white.opacity(0.8)).lineLimit(3) }
            HStack(spacing: 12) {
                NavigationLink { DetailView(media: media, app: app, playImmediately: true) } label: {
                    Label(DesktopInterfaceText.value("Start Watching"), image: "ui-play-filled").font(HarborTheme.font(15, weight: .semibold)).padding(.horizontal, 22).frame(minHeight: 48).foregroundStyle(HarborTheme.background).background(HarborTheme.ink, in: .capsule)
                }.buttonStyle(.plain).accessibilityIdentifier("anime-start-watching")
                Button {
                    if app.user == nil { app.showAccount = true }
                    else { Task { await app.library.toggleBookmark(media); if app.library.error == nil { withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7)) { hint = "saved"; hintRevision &+= 1 } } } }
                } label: {
                    Image(saved ? "desktop-check" : "desktop-plus").resizable().scaledToFit().frame(width: 18, height: 18).frame(width: 48, height: 48).background(saved ? HarborTheme.ink.opacity(0.15) : HarborTheme.background.opacity(0.8), in: .circle)
                }.buttonStyle(.plain).disabled(app.library.busy || app.library.loading)
                    .accessibilityLabel(DesktopInterfaceText.value(saved ? "Remove from saved" : "Save for later"))
                    .modifier(HarborActionHint(id: "saved", title: DesktopInterfaceText.value(saved ? "Remove from saved" : "Save for later"), selected: hint))
                if let rating = media.imdbRating { Text("\(media.ratingSource ?? "IMDb") \(rating)").font(HarborTheme.font(12, weight: .semibold)).foregroundStyle(.white.opacity(0.8)) }
            }
            if let error = app.library.error { Text(error).font(.caption).foregroundStyle(.orange) }
        }.padding(.horizontal, 20).padding(.bottom, 14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .task(id: hintRevision) { guard hint != nil else { return }; do { try await Task.sleep(for: .seconds(1.8)); withAnimation { hint = nil } } catch {} }
    }
}

struct HarborSeriesHero: View {
    let metas: [Media]
    let app: AppModel
    @State private var selected: String?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var slides: [Media] { Array(metas.prefix(5)) }
    private var index: Int { slides.firstIndex { $0.identity == selected } ?? 0 }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("SHOWTIME").font(HarborTheme.font(10, weight: .semibold)).tracking(4).foregroundStyle(.secondary)
                Text(DesktopInterfaceText.value("Tonight's main event")).font(HarborTheme.displayFont(30))
                Text(DesktopInterfaceText.value("Series for the part of the day you actually look forward to.")).font(HarborTheme.font(14)).foregroundStyle(.secondary)
            }.padding(.horizontal, 20)
            if !slides.isEmpty {
                GeometryReader { bounds in
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(slides, id: \.identity) { media in
                                HarborSeriesSlide(media: media, app: app).frame(width: bounds.size.width * 0.86, height: 310)
                                    .opacity(selected == nil || selected == media.identity ? 1 : 0.55)
                                    .scrollTransition { content, phase in content.scaleEffect(phase.isIdentity ? 1 : 0.9) }
                                    .id(media.identity)
                            }
                        }.scrollTargetLayout()
                    }.contentMargins(.horizontal, bounds.size.width * 0.07, for: .scrollContent)
                        .scrollTargetBehavior(.viewAligned).scrollPosition(id: $selected, anchor: .center).scrollIndicators(.hidden)
                }.frame(height: 310)
                HarborHeroPips(count: slides.count, selected: index) { position in withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.72)) { selected = slides[position].identity } }
            }
        }.padding(.top, 18).accessibilityIdentifier("series-original-hero")
            .onChange(of: slides.map(\.identity)) { _, identities in if !identities.contains(selected ?? "") { selected = identities.first } }
            .task(id: "\(scenePhase == .active)|\(reduceMotion)|\(selected ?? "")|\(slides.map(\.identity).joined())") {
                guard scenePhase == .active, !reduceMotion, slides.count > 1 else { return }
                do { try await Task.sleep(for: .milliseconds(9500)); try Task.checkCancellation(); withAnimation(.easeInOut(duration: 0.72)) { selected = slides[(index + 1) % slides.count].identity } } catch {}
            }
    }
}

private struct HarborSeriesSlide: View {
    let media: Media
    let app: AppModel
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Artwork(url: media.background, fallback: media.fallbackBackground, fallbacks: [media.poster].compactMap { $0 }, maxPixels: 1200)
            LinearGradient(colors: [.clear, .black.opacity(0.35), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom).allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 13) {
                NavigationLink(value: media) { HarborHeroTitle(media: media, size: 28, height: 76) }.buttonStyle(.plain)
                HStack(spacing: 8) { if let year = media.releaseInfo { Text(year) }; if let genre = media.genres?.first { Text(genre.uppercased()) } }.font(HarborTheme.font(11)).tracking(1).foregroundStyle(.white.opacity(0.75))
                HStack(spacing: 8) {
                    NavigationLink { DetailView(media: media, app: app, playImmediately: true) } label: { Label("Reproducir", image: "ui-play-filled").font(HarborTheme.font(13, weight: .semibold)).padding(.horizontal, 16).frame(minHeight: 44).foregroundStyle(.black).background(.white, in: .capsule) }.buttonStyle(.plain)
                    NavigationLink(value: media) { Text("Episodios").font(HarborTheme.font(13, weight: .medium)).padding(.horizontal, 16).frame(minHeight: 44).background(HarborTheme.background.opacity(0.8), in: .capsule) }.buttonStyle(.plain)
                }
            }.padding(18)
        }.clipShape(.rect(cornerRadius: 12))
    }
}

struct HarborHeroPips: View {
    let count: Int
    let selected: Int
    let select: (Int) -> Void
    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { index in
                Button { select(index) } label: { Capsule().fill(selected == index ? HarborTheme.ink : HarborTheme.ink.opacity(0.3)).frame(width: selected == index ? 26 : 6, height: 4).frame(minWidth: 28, minHeight: 44).contentShape(Rectangle()) }
                    .buttonStyle(.plain).accessibilityLabel("Destacado \(index + 1)").accessibilityAddTraits(selected == index ? [.isSelected] : [])
            }
        }.frame(maxWidth: .infinity)
    }
}
