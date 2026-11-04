import SwiftUI

/// Compact port of Desktop's MusicArtistOverview and MusicWhereToBuy
/// (music-artist-overview.tsx). The data comes from the pinned original
/// artist-profile module; the gallery, tour extras, linked biography and
/// genre navigation of the full artist page are not part of this view.
@MainActor struct MusicArtistOverviewView: View {
    let artist: MusicArtistReference
    let client: MusicArtistClient
    let catalog: any MusicCatalogCalling
    @AppStorage("uiLanguage") private var language = "es"
    @State private var profile: MusicArtistProfile?
    @State private var expanded = false
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }

    var body: some View {
        Group { if let profile { story(profile) } }
            .task(id: artist.id + "|" + language) {
                profile = nil; expanded = false
                do {
                    let value = try await client.profile(artist, language: InterfaceLanguage.resolve(language))
                    try Task.checkCancellation(); profile = value
                } catch { }
            }
    }

    @ViewBuilder private func story(_ profile: MusicArtistProfile) -> some View {
        let image = MusicArtistLinks.imageURL(profile.artwork) ?? MusicArtistLinks.imageURL(artist.artwork)
        let links = profile.links.filter { $0.kind != "merch" }
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                if let image {
                    AsyncImage(url: image) { $0.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.15) }
                        .frame(width: 96, height: 96).clipShape(.rect(cornerRadius: 10)).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(image != nil ? profile.name : text("music.artist.about")).font(.title3.bold())
                    biography(profile)
                    facts(profile)
                    genres(profile)
                    if let url = MusicArtistLinks.wikipedia(profile.biographyUrl) {
                        Link(destination: url) { Label("Wikipedia", systemImage: "arrow.up.right") }.font(.caption)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if !profile.members.isEmpty { connections(profile) }
            if !links.isEmpty { aroundWeb(links) }
            if let url = URL(string: "https://musicbrainz.org/artist/" + profile.id) {
                Link(destination: url) { Label("MusicBrainz", systemImage: "arrow.up.right") }.font(.caption)
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("music-artist-overview")
    }

    @ViewBuilder private func biography(_ profile: MusicArtistProfile) -> some View {
        if let body = profile.biography, !body.isEmpty {
            Text(body).font(.subheadline).foregroundStyle(.secondary).lineLimit(expanded ? nil : 6)
            if body.count > 320 {
                Button(text(expanded ? "music.artist.readLess" : "music.artist.readMore")) { expanded.toggle() }
                    .font(.caption.weight(.semibold)).accessibilityAddTraits(.isButton)
            }
        }
    }

    @ViewBuilder private func facts(_ profile: MusicArtistProfile) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let origin = profile.origin, !origin.isEmpty { fact("music.artist.origin", origin) }
            if let began = profile.began, !began.isEmpty {
                fact("music.artist.began", began + ((profile.ended ?? "").isEmpty ? "" : " – " + (profile.ended ?? "")))
            }
            if !profile.aliases.isEmpty { fact("music.artist.aliases", profile.aliases.joined(separator: " · ")) }
        }
    }
    private func fact(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(text(key)).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.caption)
        }
    }

    @ViewBuilder private func genres(_ profile: MusicArtistProfile) -> some View {
        if !profile.genres.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(profile.genres, id: \.self) { genre in
                    Text(genre).font(.caption).lineLimit(1).padding(.horizontal, 10).padding(.vertical, 5)
                        .background(HarborTheme.surface, in: .capsule)
                }
            }
        }
    }

    private func connections(_ profile: MusicArtistProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text("music.artist.connections")).font(.headline)
            ForEach(profile.members) { member in
                MusicCatalogLink(item: .artist(member.catalog), client: catalog) {
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle").foregroundStyle(.secondary)
                        Text(member.name).font(.subheadline)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }.padding(12).background(HarborTheme.surface, in: .rect(cornerRadius: 10))
                }.buttonStyle(.plain)
            }
        }
    }

    private func aroundWeb(_ links: [MusicArtistProfile.Link]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text("music.artist.aroundWeb")).font(.headline)
            ForEach(links, id: \.self) { link in
                if let url = URL(string: link.url) { MusicArtistLinkRow(link: link, url: url) }
            }
        }
    }
}

/// One outbound artist link, labelled like Desktop: a provider's own name for
/// sources, otherwise the link kind with the host as its caption.
@MainActor struct MusicArtistLinkRow: View {
    let link: MusicArtistProfile.Link
    let url: URL
    var body: some View {
        Link(destination: url) {
            HStack(spacing: 10) {
                Image(systemName: link.kind == "store" ? "bag" : link.kind == "tour" ? "ticket" : link.kind == "social" ? "person.2" : "globe")
                    .foregroundStyle(.secondary).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(link.kind == "source" ? link.name : DesktopInterfaceText.value(link.kind == "tour" ? "music.extras.tour" : "music.artist." + link.kind)).font(.subheadline)
                    if link.kind != "source" { Text(link.name).font(.caption2).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
            }.padding(12).background(HarborTheme.surface, in: .rect(cornerRadius: 10))
        }.buttonStyle(.plain)
    }
}

@MainActor struct MusicWhereToBuyView: View {
    let track: MusicTrack
    let artist: MusicArtistReference?
    let client: MusicArtistClient
    @State private var opened = false
    @State private var profile: MusicArtistProfile?
    var body: some View {
        let stores = (profile?.links ?? []).filter { $0.kind == "store" || $0.kind == "merch" }
        DisclosureGroup(isExpanded: $opened) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(stores, id: \.self) { link in
                    if let url = URL(string: link.url) { MusicArtistLinkRow(link: link, url: url) }
                }
                if let url = MusicArtistLinks.bandcampSearch(artist: track.artist, title: track.title) {
                    Link(destination: url) {
                        HStack {
                            Label(DesktopInterfaceText.value("music.buy.search", variables: ["store": "Bandcamp"]), systemImage: "bag")
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right").font(.caption)
                        }.font(.subheadline)
                    }
                }
            }.padding(.top, 8)
        } label: {
            Label(DesktopInterfaceText.value("music.buy.title"), systemImage: "bag")
        }.accessibilityIdentifier("music-where-to-buy")
            .task(id: track.id + "|" + String(opened)) {
                profile = nil
                guard opened, !track.artist.isEmpty else { return }
                do {
                    var canonical = artist
                    if canonical == nil { canonical = try await client.canonicalArtist(for: track) }
                    guard let canonical else { return }
                    let value = try await client.profile(canonical, language: "en")
                    try Task.checkCancellation(); profile = value
                } catch { }
            }
    }
}

/// URL policy shared by the artist views: only public https destinations the
/// original module can return are opened or loaded.
enum MusicArtistLinks {
    static func imageURL(_ text: String?) -> URL? {
        guard let text, let url = URL(string: text), url.scheme == "https",
              let host = url.host?.lowercased(), host == "upload.wikimedia.org" || host == "commons.wikimedia.org" || host.hasSuffix(".dzcdn.net") else { return nil }
        return url
    }
    static func wikipedia(_ text: String?) -> URL? {
        guard let text, let url = URL(string: text), url.scheme == "https", let host = url.host?.lowercased(),
              host.range(of: #"^[a-z]{2,3}\.wikipedia\.org$"#, options: .regularExpression) != nil else { return nil }
        return url
    }
    static func bandcampSearch(artist: String, title: String) -> URL? {
        let query = (artist + " " + title).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        var components = URLComponents(string: "https://bandcamp.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }
}
