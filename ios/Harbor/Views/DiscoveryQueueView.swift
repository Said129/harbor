import SwiftUI

struct DiscoveryQueueView: View {
    let items: [Media]
    let app: AppModel
    @State private var owner: String
    @State private var activeID: String?
    @State private var enriched: [String: Media] = [:]
    @State private var hint: String?
    @State private var hintRevision = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @MainActor init(items: [Media], app: AppModel) {
        self.items = items; self.app = app
        _owner = State(initialValue: app.library.owner)
    }
    private var pool: [Media] {
        guard owner == app.library.owner else { return [] }
        let watched = Set(app.library.items.filter { $0.watched || $0.continuing }.map(\.id))
        return items.filter { !watched.contains($0.id) && app.library.discovery.vote(for: $0) == nil && !app.library.discovery.isQueueItemHidden($0.id) }
    }
    private var index: Int { pool.firstIndex { $0.identity == activeID } ?? 0 }
    private var current: Media? { pool.indices.contains(index) ? (enriched[pool[index].identity] ?? pool[index]) : nil }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(DesktopVoyage.copy("Discovery Queue")).font(HarborTheme.displayFont(20))
                    if let media = current {
                        DiscoveryQueueHero(media: media, app: app, position: index, total: pool.count,
                                           onPrevious: { jump(index - 1) }, onNext: { jump(index + 1) },
                                           onSkip: { removeCurrent(permanently: false) }, onNotInterested: { removeCurrent(permanently: true) },
                                           onSaved: { showHint(DesktopVoyage.copy(app.library.bookmarked(media) ? "Saved" : "Save")) })
                            .frame(minHeight: min(600, max(420, geometry.size.height * 0.72)))
                            .id(media.identity).transition(.opacity)
                        strip
                    } else {
                        Text(DesktopVoyage.copy(MetadataPreferences.shared.configuration().tmdbKey.isEmpty
                             ? "Add a TMDB key in Settings to unlock the full discovery feed."
                             : "No picks loaded. TMDB might be unreachable."))
                            .font(HarborTheme.font(15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            .padding(32).frame(maxWidth: .infinity, minHeight: 300)
                            .background(HarborTheme.surface.opacity(0.3), in: .rect(cornerRadius: 16))
                    }
                    if let error = app.library.discovery.error ?? app.library.error { Text(error).font(HarborTheme.font(13)).foregroundStyle(.orange) }
                }.padding(.horizontal, 20).padding(.vertical, 20)
            }.scrollIndicators(.hidden).accessibilityIdentifier("discovery-queue-scroll")
        }.background(HarborTheme.background)
            .navigationTitle("").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .accessibilityIdentifier("discovery-queue")
            .onChange(of: app.library.owner) { _, _ in enriched = [:]; activeID = nil; hint = nil; dismiss() }
            .task(id: current?.identity) {
                guard let media = current, enriched[media.identity] == nil else { return }
                do {
                    let detailed = try await app.service.metadata(media, addons: app.addons)
                    try Task.checkCancellation()
                    guard owner == app.library.owner else { return }
                    enriched[media.identity] = detailed
                } catch {}
            }
            .safeAreaInset(edge: .bottom) {
                if let hint {
                    Text(hint).font(HarborTheme.font(12, weight: .medium)).multilineTextAlignment(.center)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(ThemePreferences.shared.color("elevated"), in: .rect(cornerRadius: 8))
                        .padding(.horizontal, 20).padding(.bottom, 8).allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .task(id: hintRevision) {
                guard hint != nil else { return }
                do { try await Task.sleep(for: .seconds(1.8)); withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { hint = nil } } catch {}
            }
    }
    private var strip: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(DesktopVoyage.copy("Queue")).font(HarborTheme.font(11, weight: .semibold)).textCase(.uppercase).tracking(2.64).foregroundStyle(.secondary)
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(Array(pool.enumerated()), id: \.element.identity) { offset, seed in
                            let media = enriched[seed.identity] ?? seed
                            Button { jump(offset) } label: {
                                ZStack(alignment: .bottomLeading) {
                                    Artwork(url: media.background ?? media.poster, fallback: media.fallbackBackground, fallbacks: [media.poster].compactMap { $0 }, maxPixels: 450)
                                    LinearGradient(colors: [.clear, HarborTheme.background.opacity(0.92)], startPoint: .center, endPoint: .bottom)
                                    HarborHeroTitle(media: media, size: 12.5, height: 38).frame(maxWidth: 164, alignment: .leading).padding(.horizontal, 10).padding(.bottom, 8)
                                }.frame(width: 200, height: 112.5).clipShape(.rect(cornerRadius: 6))
                                    .overlay { RoundedRectangle(cornerRadius: 6).stroke(offset == index ? HarborTheme.accent : .clear, lineWidth: 2) }
                                    .opacity(offset < index ? 0.5 : 1).contentShape(Rectangle())
                            }.buttonStyle(.plain).id(seed.identity).accessibilityLabel(media.name)
                                .accessibilityAddTraits(offset == index ? .isSelected : [])
                        }
                    }.padding(3)
                }.scrollIndicators(.hidden)
                    .onChange(of: current?.identity, initial: true) { _, identity in
                        guard let identity else { return }
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { proxy.scrollTo(identity, anchor: .center) }
                    }
            }
        }
    }
    private func jump(_ next: Int) {
        guard pool.indices.contains(next) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { activeID = pool[next].identity }
    }
    private func removeCurrent(permanently: Bool) {
        guard let media = current, owner == app.library.owner else { return }
        let remaining = pool.filter { $0.id != media.id }
        let next = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].identity
        let preferences = app.library.discovery
        var saved = false
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) {
            saved = permanently ? preferences.blockQueueItem(media.id) : preferences.snoozeQueueItem(media.id)
            if saved { activeID = next }
        }
        guard saved else { return }
        showHint(DesktopVoyage.copy(permanently ? "Never shown again" : "Back in two weeks"))
    }
    private func showHint(_ value: String) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { hint = value; hintRevision &+= 1 }
    }
}

private struct DiscoveryQueueHero: View {
    let media: Media
    let app: AppModel
    let position: Int
    let total: Int
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onSkip: () -> Void
    let onNotInterested: () -> Void
    let onSaved: () -> Void
    private var saved: Bool { app.library.bookmarked(media) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(String(format: "%02d / %02d", position + 1, total)).font(HarborTheme.font(12, weight: .semibold)).tracking(2.64).accessibilityIdentifier("discovery-queue-position")
                Spacer()
                NavigationLink { DetailView(media: media, app: app) } label: {
                    Image("discovery-queue-info").resizable().scaledToFit().frame(width: 28, height: 28).frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel(DesktopVoyage.copy("See details")).accessibilityIdentifier("discovery-queue-details")
            }
            HStack {
                arrow("desktop-chevron-left", label: "Previous", disabled: position == 0, action: onPrevious)
                Spacer(minLength: 0)
                arrow("desktop-chevron-right", label: "Next", disabled: position + 1 >= total, action: onNext)
            }.frame(minHeight: 80)
            Spacer(minLength: 0)
            Text(DesktopVoyage.copy(media.type == "series" ? "Series" : "Movies")).font(HarborTheme.font(11.5, weight: .semibold)).textCase(.uppercase).tracking(2.53)
                .padding(.horizontal, 12).padding(.vertical, 4).foregroundStyle(HarborTheme.background).background(HarborTheme.accent.opacity(0.9), in: .capsule)
            Text(media.name).font(HarborTheme.displayFont(34)).lineSpacing(1.7).lineLimit(2).minimumScaleFactor(0.85).shadow(color: .black.opacity(0.55), radius: 16, y: 2).accessibilityIdentifier("discovery-queue-title")
            metadata
            if let description = media.description, !description.isEmpty { Text(description).font(HarborTheme.font(15.5)).lineSpacing(5).foregroundStyle(HarborTheme.ink.opacity(0.8)).lineLimit(2) }
            actions.padding(.top, 8)
        }.padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 28)
            .foregroundStyle(HarborTheme.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .background {
                ZStack {
                    Artwork(url: media.background ?? media.poster, fallback: media.fallbackBackground, fallbacks: [media.poster].compactMap { $0 }, maxPixels: 1280)
                    LinearGradient(stops: [.init(color: HarborTheme.background.opacity(0.97), location: 0), .init(color: HarborTheme.background.opacity(0.86), location: 0.12), .init(color: HarborTheme.background.opacity(0.6), location: 0.26), .init(color: HarborTheme.background.opacity(0.33), location: 0.4), .init(color: HarborTheme.background.opacity(0.12), location: 0.54), .init(color: .clear, location: 0.7)], startPoint: .bottom, endPoint: .top)
                    LinearGradient(colors: [HarborTheme.background.opacity(0.62), .clear, .clear], startPoint: .leading, endPoint: .trailing)
                }.accessibilityHidden(true)
            }.clipShape(.rect(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(HarborTheme.ink.opacity(0.08), lineWidth: 1) }
    }
    private var metadata: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                if let year = media.releaseInfo { Text(year) }
                if let runtime = media.runtime { Text(runtime) }
                if let rating = media.imdbRating {
                    HStack(spacing: 6) {
                        Text(media.ratingSource ?? "IMDb").font(HarborTheme.font(9, weight: .bold)).foregroundStyle(.black).padding(2).background(media.ratingSource == "TMDB" ? Color.mint : .yellow, in: .rect(cornerRadius: 2))
                        Text(rating)
                    }
                }
            }
            if let genres = media.genres, !genres.isEmpty { Text(genres.prefix(3).joined(separator: ", ")) }
        }.font(HarborTheme.font(14)).foregroundStyle(HarborTheme.ink.opacity(0.85))
    }
    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { play; save }
                VStack(alignment: .leading, spacing: 8) { play; save }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { skip; notInterested }
                VStack(alignment: .leading, spacing: 8) { skip; notInterested }
            }
        }
    }
    private var play: some View {
        NavigationLink { DetailView(media: media, app: app, playImmediately: true) } label: {
            HStack(spacing: 10) { glyph("ui-play-filled"); Text(DesktopVoyage.copy("Play now")) }
                .font(HarborTheme.font(15, weight: .semibold)).padding(.horizontal, 28).frame(minHeight: 48)
                .foregroundStyle(HarborTheme.background).background(HarborTheme.ink, in: .capsule)
        }.buttonStyle(.plain).accessibilityIdentifier("discovery-queue-play")
    }
    private var save: some View {
        Button {
            if app.user == nil { app.showAccount = true }
            else {
                let owner = app.library.owner
                Task { await app.library.toggleBookmark(media); if owner == app.library.owner, app.library.error == nil { onSaved() } }
            }
        } label: { chip(saved ? "Saved" : "Save", asset: "ui-save-banner", active: saved) }
            .buttonStyle(.plain).disabled(app.library.busy || app.library.loading).accessibilityIdentifier("discovery-queue-save")
    }
    private var skip: some View {
        Button(action: onSkip) { chip("Skip", asset: "ui-skip-fwd") }.buttonStyle(.plain).disabled(!app.library.discovery.ready)
            .accessibilityHint(DesktopVoyage.copy("Back in two weeks")).accessibilityIdentifier("discovery-queue-skip")
    }
    private var notInterested: some View {
        Button(action: onNotInterested) { chip("Not interested", asset: "ui-thumbs-up", rotation: 180) }.buttonStyle(.plain).disabled(!app.library.discovery.ready)
            .accessibilityHint(DesktopVoyage.copy("Never shown again")).accessibilityIdentifier("discovery-queue-block")
    }
    private func chip(_ label: String, asset: String, active: Bool = false, rotation: Double = 0) -> some View {
        HStack(spacing: 8) { glyph(asset).rotationEffect(.degrees(rotation)); Text(DesktopVoyage.copy(label)) }
            .font(HarborTheme.font(14, weight: .medium)).padding(.horizontal, 20).frame(minHeight: 48).fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(active ? HarborTheme.accent : HarborTheme.ink.opacity(0.85))
            .background(active ? HarborTheme.accent.opacity(0.15) : HarborTheme.background.opacity(0.3), in: .capsule)
            .overlay { Capsule().stroke(active ? HarborTheme.accent.opacity(0.6) : HarborTheme.ink.opacity(0.15), lineWidth: 1) }
    }
    private func glyph(_ asset: String) -> some View { Image(asset).resizable().scaledToFit().frame(width: 18, height: 18).accessibilityHidden(true) }
    private func arrow(_ asset: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(asset).resizable().scaledToFit().frame(width: 38, height: 38).frame(width: 44, height: 44).shadow(color: .black.opacity(0.8), radius: 9, y: 2) }
            .buttonStyle(.plain).disabled(disabled).opacity(disabled ? 0.2 : 0.85).accessibilityLabel(DesktopVoyage.copy(label))
    }
}
