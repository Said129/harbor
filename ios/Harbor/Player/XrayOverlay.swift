import SwiftUI

/// Desktop's X-Ray cast overlay (`components/player/xray/xray-overlay.tsx`) without the live face scan. A button under the top row
/// opens a rail of the title's cast. "View all" opens the browser with the cast and the about text, and a tap opens the person's
/// page. Nothing pauses, and the trailer is not played. The cast is the title's loaded details (`PlaybackSession.xrayTitle`), so it
/// stays empty until those details load. The rules are in `XrayRules`. A modifier of its own keeps the player's modifier chain quick
/// to type-check.
struct XrayOverlayDriver: ViewModifier {
    let session: PlaybackSession
    let state: PlayerState
    /// The player's controls are showing and the resume prompt is not. The open rail stays up while the controls hide, as on Desktop.
    let visible: Bool
    @AppStorage(XrayRules.enabledKey) private var enabled = false
    @Environment(\.customListApp) private var app
    @State private var railOpen = false
    @State private var person: XrayPerson?

    private var title: Media? { session.xrayTitle }
    private var people: [XrayPerson] { XrayRules.people(from: title?.details?.cast ?? []) }
    private var hasTMDBKey: Bool { !MetadataPreferences.shared.tmdbKey.isEmpty }
    /// The overlay needs a loaded picture: Desktop shows it while playing, not on the connecting or failed screens.
    /// Only a title with detail context has a cast to show; live TV, search links, downloads and local files have none.
    private var playing: Bool { enabled && title != nil && state.loaded && state.error == nil }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) { xrayLayer }
            .sheet(item: $person) { item in
                if let app { XrayPersonSheet(personID: item.id, app: app) }
            }
            .onChange(of: session.id) { _, _ in
                railOpen = false
                person = nil
            }
    }

    @ViewBuilder private var xrayLayer: some View {
        if playing && railOpen {
            XrayRail(people: people, hasTMDBKey: hasTMDBKey, title: title, app: app,
                     onOpen: { person = $0 }, onClose: { railOpen = false })
        } else if playing && visible {
            Button { railOpen = true } label: {
                Label(DesktopInterfaceText.value("X-Ray"), systemImage: "face.viewfinder")
                    .font(HarborTheme.font(13, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.7), radius: 3, y: 1)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .padding(.leading, 20).padding(.top, 72)
            .accessibilityIdentifier("player-xray")
        }
    }
}

/// Desktop's `XrayRail`: the header with "View all" and close, a status line when there is no cast, and the cast list.
private struct XrayRail: View {
    let people: [XrayPerson]
    let hasTMDBKey: Bool
    let title: Media?
    let app: AppModel?
    let onOpen: (XrayPerson) -> Void
    let onClose: () -> Void
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var browserOpen = false

    private var status: String? {
        switch XrayRules.railState(people: people, hasTMDBKey: hasTMDBKey) {
        case .cast: return nil
        case .needsTMDBKey: return DesktopInterfaceText.value("Add a TMDB key in Settings to identify the cast.")
        case .empty: return DesktopInterfaceText.value("No cast photos are available for this title.")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(DesktopInterfaceText.value("X-Ray"), systemImage: "face.viewfinder")
                    .font(HarborTheme.font(11, weight: .bold)).textCase(.uppercase)
                Button(DesktopInterfaceText.value("View all")) { browserOpen = true }
                    .font(HarborTheme.font(12, weight: .semibold))
                Spacer(minLength: 0)
                Button(action: onClose) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel(DesktopInterfaceText.value("Close"))
            }
            .foregroundStyle(.white)
            if let status {
                Text(status).font(HarborTheme.font(12)).foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !people.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(people) { person in
                            Button { onOpen(person) } label: { XrayRow(person: person) }.buttonStyle(.plain)
                        }
                    }
                }
                // Landscape phones are short: the rail stops above the seek bar instead of running to the bottom edge.
                .frame(maxHeight: verticalSizeClass == .compact ? 200 : 380)
            }
        }
        .padding(12)
        .frame(width: 300, alignment: .leading)
        .background(.black.opacity(0.72), in: .rect(cornerRadius: 14))
        .padding(.leading, 20).padding(.top, 72)
        .sheet(isPresented: $browserOpen) {
            XrayBrowserSheet(title: title, people: people, hasTMDBKey: hasTMDBKey, app: app)
        }
    }
}

/// Desktop's `XrayRailCard`: a photo, the name and the character.
private struct XrayRow: View {
    let person: XrayPerson

    var body: some View {
        HStack(spacing: 12) {
            XrayPhoto(person: person, size: 48, corner: 11)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name).font(HarborTheme.font(14, weight: .semibold)).lineLimit(1)
                if !person.character.isEmpty {
                    Text(person.character).font(HarborTheme.font(12)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Desktop's `XrayBrowser`: the cast grid and the about text, under one close button.
private struct XrayBrowserSheet: View {
    let title: Media?
    let people: [XrayPerson]
    let hasTMDBKey: Bool
    let app: AppModel?
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: BrowserTab?
    @State private var opened: XrayPerson?

    private enum BrowserTab: Hashable { case cast, about }

    private var overview: String { title?.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
    private var tagline: String { title?.details?.tagline?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }

    private var tabs: [BrowserTab] {
        var list: [BrowserTab] = []
        if !people.isEmpty { list.append(.cast) }
        if !overview.isEmpty || !tagline.isEmpty { list.append(.about) }
        return list
    }

    private var selected: BrowserTab? {
        if let chosen, tabs.contains(chosen) { return chosen }
        return tabs.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Label(DesktopInterfaceText.value("X-Ray"), systemImage: "face.viewfinder")
                    .font(HarborTheme.font(12, weight: .bold)).textCase(.uppercase)
                ForEach(tabs, id: \.self) { item in
                    Button { chosen = item } label: {
                        Text(label(item)).font(HarborTheme.font(14, weight: .semibold))
                            .foregroundStyle(selected == item ? HarborTheme.ink : HarborTheme.ink.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel(DesktopInterfaceText.value("Close"))
            }
            ScrollView {
                content.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(HarborTheme.background.ignoresSafeArea())
        .sheet(item: $opened) { item in
            if let app { XrayPersonSheet(personID: item.id, app: app) }
        }
    }

    @ViewBuilder private var content: some View {
        if let selected {
            switch selected {
            case .cast:
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 14, alignment: .top)], alignment: .leading, spacing: 18) {
                    ForEach(people) { person in
                        Button { opened = person } label: { XrayTile(person: person) }.buttonStyle(.plain)
                    }
                }
            case .about:
                VStack(alignment: .leading, spacing: 12) {
                    if !tagline.isEmpty {
                        Text(tagline).font(HarborTheme.font(17, weight: .medium)).foregroundStyle(HarborTheme.ink)
                    }
                    if !overview.isEmpty {
                        Text(overview).font(HarborTheme.font(15)).foregroundStyle(HarborTheme.ink.opacity(0.85))
                    }
                }
            }
        } else {
            Text(hasTMDBKey ? DesktopInterfaceText.value("No cast information for this title.") : DesktopInterfaceText.value("Add a TMDB key in Settings to see the cast, crew, and details."))
                .font(HarborTheme.font(14)).foregroundStyle(HarborTheme.ink.opacity(0.55))
                .frame(maxWidth: .infinity, minHeight: 220)
        }
    }

    private func label(_ item: BrowserTab) -> String {
        switch item {
        case .cast: return DesktopInterfaceText.value("Cast")
        case .about: return DesktopInterfaceText.value("About")
        }
    }
}

/// Desktop's `XrayTile`: a square photo with the name and the character under it.
private struct XrayTile: View {
    let person: XrayPerson

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            XrayPhoto(person: person, size: 104, corner: 16)
            Text(person.name).font(HarborTheme.font(13, weight: .semibold)).lineLimit(2)
            if !person.character.isEmpty {
                Text(person.character).font(HarborTheme.font(12)).foregroundStyle(HarborTheme.ink.opacity(0.55)).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// The photo from TMDB, or the initials on a plain tile while there is none (or it has not loaded).
private struct XrayPhoto: View {
    let person: XrayPerson
    let size: CGFloat
    let corner: CGFloat

    var body: some View {
        ZStack {
            Rectangle().fill(.white.opacity(0.08))
            Text(XrayRules.initials(person.name))
                .font(HarborTheme.font(size * 0.3, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            if let photo = person.photo {
                Artwork(url: photo, maxPixels: 240, showsPlaceholder: false)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: corner))
        .accessibilityHidden(true)
    }
}

/// The person's page from the cast page (`PersonView`), in its own navigation stack with a close button.
private struct XrayPersonSheet: View {
    let personID: Int
    let app: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PersonView(personID: personID, app: app)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(DesktopInterfaceText.value("Close")) { dismiss() }
                    }
                }
        }
    }
}
