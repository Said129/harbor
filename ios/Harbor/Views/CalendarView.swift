import SwiftUI

struct CalendarView: View {
    let app: AppModel
    @State private var model = CalendarModel()
    @State private var month = Date()
    @State private var selected = Date()
    @State private var kind = "all"
    @State private var watchlistOnly = false
    @State private var animeDub = false
    @State private var showFilters = false
    private let customCalendar = CustomCalendarStore.shared
    @AppStorage("calendar.source") private var sourceRaw = CalendarSource.library.rawValue
    @AppStorage("calendar.monday") private var monday = false
    @AppStorage("calendar.large") private var large = false
    private let interfaceLocale = Locale(identifier: "es")
    private var calendar: Calendar { var calendar = Calendar.current; calendar.locale = interfaceLocale; calendar.firstWeekday = monday ? 2 : 1; return calendar }
    private var source: CalendarSource { CalendarSource(rawValue: sourceRaw) ?? .library }
    private var traktConnected: Bool { TraktAccountStore.forOwner(app.personalOwner).session != nil }
    private var simklConnected: Bool { SimklAccountStore.forOwner(app.personalOwner).session != nil }
    /// Desktop's `filtered`: All upcoming holds movies and TV only and can be narrowed to the library; the other sources show everything they found.
    private var shown: [ReleaseEvent] {
        switch source {
        case .library, .simkl, .simklAnticipated:
            return model.events.filter { kind == "all" || $0.kind == kind }
        case .all:
            let names = watchlistOnly ? Set(app.library.items.compactMap(\.media).map { CalendarSources.libraryKey(name: $0.name, isSeries: $0.type != "movie") }) : []
            return model.events.filter { event in
                !event.isAnime && (kind == "all" || event.kind == kind)
                    && (!watchlistOnly || names.contains(CalendarSources.libraryKey(name: event.media.name, isSeries: event.media.type != "movie")))
            }
        case .trakt, .anticipated, .anime, .custom:
            return model.events
        }
    }
    private var loadID: String {
        let period = "\(calendar.component(.year, from: month))-\(calendar.component(.month, from: month))"
        switch source {
        case .library: return "\(app.library.owner)|\(period)|\(app.library.items.map { $0.id + $0.modified }.joined())|library"
        case .all: return "\(app.personalOwner)|\(period)|all|\(MetadataPreferences.shared.tmdbKey.hashValue)|\(MetadataPreferences.shared.region)"
        case .trakt: return "\(app.personalOwner)|\(period)|trakt|\(traktConnected)"
        case .simkl: return "\(app.personalOwner)|\(period)|simkl|\(simklConnected)"
        case .anticipated, .simklAnticipated: return "\(period)|\(source.rawValue)"
        case .anime: return "\(period)|anime|\(animeDub)"
        case .custom: return "\(app.personalOwner)|\(period)|custom|\(customCalendar.value.hashValue)|\(MetadataPreferences.shared.tmdbKey.hashValue)|\(MetadataPreferences.shared.region)|\(traktConnected)"
        }
    }
    private var daily: [ReleaseEvent] { shown.filter { calendar.isDate($0.date, inSameDayAs: selected) } }
    private var cells: [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: month), let days = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let offset = (calendar.component(.weekday, from: interval.start) - calendar.firstWeekday + 7) % 7
        let count = ((days.count + offset + 6) / 7) * 7
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0 - offset, to: interval.start) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HarborPageHeading(title: "Calendario", eyebrow: "Estrenos")
                HStack {
                    Button { changeMonth(-1) } label: { monthArrow(previous: true) }.buttonStyle(.plain).accessibilityLabel("Mes anterior")
                    Spacer()
                    HStack(spacing: 8) { Image("nav-calendar").resizable().scaledToFit().frame(width: 14, height: 14).foregroundStyle(HarborTheme.ink.opacity(0.45)); Text(month.formatted(.dateTime.month(.wide).year().locale(interfaceLocale))).font(HarborTheme.font(14, weight: .semibold)) }.padding(.horizontal, 16).frame(minHeight: 40).background(HarborTheme.surface.opacity(0.2), in: .capsule).overlay { Capsule().stroke(HarborTheme.ink.opacity(0.05), lineWidth: 1) }
                    Spacer()
                    Button { changeMonth(1) } label: { monthArrow(previous: false) }.buttonStyle(.plain).accessibilityLabel("Mes siguiente")
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        HarborPill(title: "Hoy") { month = Date(); selected = Date() }
                        ForEach(CalendarSource.offered(traktConnected: traktConnected, simklConnected: simklConnected), id: \.self) { option in
                            HarborPill(title: DesktopInterfaceText.value(option.label), selected: source == option, icon: option.icon) { sourceRaw = option.rawValue }
                                .accessibilityHint(DesktopInterfaceText.value(option.hint)).accessibilityIdentifier("calendar-source-" + option.rawValue)
                        }
                    }
                }.scrollIndicators(.hidden)
                if source == .custom {
                    HarborPill(title: DesktopInterfaceText.value("Filters") + (customCalendar.value.activeCount > 0 ? " \(customCalendar.value.activeCount)" : ""), selected: showFilters) { showFilters = true }
                        .accessibilityIdentifier("calendar-filters")
                }
                if source == .anime {
                    HStack(spacing: 6) {
                        HarborPill(title: DesktopInterfaceText.value("Sub"), selected: !animeDub) { animeDub = false }.accessibilityIdentifier("calendar-anime-sub")
                        HarborPill(title: DesktopInterfaceText.value("Dub"), selected: animeDub) { animeDub = true }.accessibilityIdentifier("calendar-anime-dub")
                    }
                }
                if source == .library || source == .simkl || source == .all || source == .simklAnticipated {
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            HarborPill(title: DesktopInterfaceText.value("All"), selected: kind == "all") { kind = "all" }
                            HarborPill(title: DesktopInterfaceText.value("Movies"), selected: kind == "movie", icon: "nav-movies") { kind = "movie" }
                            HarborPill(title: DesktopInterfaceText.value("TV"), selected: kind == "series", icon: "nav-shows") { kind = "series" }
                            if source != .all { HarborPill(title: DesktopInterfaceText.value("Anime"), selected: kind == "anime", icon: "nav-anime") { kind = "anime" } }
                            if source == .all { HarborPill(title: DesktopInterfaceText.value("Watchlist only"), selected: watchlistOnly, icon: "nav-library") { watchlistOnly.toggle() }.accessibilityIdentifier("calendar-watchlist-only") }
                        }
                    }.scrollIndicators(.hidden)
                }
                ScrollView(.horizontal) { HStack(spacing: 6) { HarborPill(title: "Empezar en lunes", selected: monday) { monday.toggle() }; HarborPill(title: "Normal", selected: !large) { large = false }; HarborPill(title: "Grande", selected: large) { large = true } } }.scrollIndicators(.hidden)
                monthGrid
                if model.loading { ProgressView("Recuperando fechas…").frame(maxWidth: .infinity) }
                if let error = model.error { Text(error).font(.caption).foregroundStyle(.orange); Button("Reintentar") { Task { await model.load(month: month, app: app, source: source, animeDub: animeDub) } } }
                Text(selected.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(interfaceLocale))).font(HarborTheme.font(17, weight: .medium))
                ForEach(daily) { event in
                    NavigationLink { DetailView(media: event.media, app: app) } label: {
                        HStack(alignment: .top, spacing: 14) {
                            Artwork(url: event.media.poster, maxPixels: 240).frame(width: 64, height: 96).clipShape(.rect(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 8) {
                                Text(event.label ?? event.media.name).font(HarborTheme.font(14, weight: .medium))
                                if let episode = event.episode { Text("\(EpisodePresentation.coordinates(episode: episode)?.caption ?? "") · \(episode.name ?? episode.title ?? "")").font(HarborTheme.font(12)).foregroundStyle(.secondary) }
                                if event.label == nil || event.hasTime { Text(event.date, style: .time).font(HarborTheme.font(12)).foregroundStyle(.secondary) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.buttonStyle(.plain)
                }
                if source == .all && MetadataPreferences.shared.tmdbKey.isEmpty {
                    CalendarEmptyCard(heading: DesktopInterfaceText.value("All upcoming needs a TMDB key"),
                                      message: DesktopInterfaceText.value("TMDB powers the firehose of every release this month. The free tier covers it. About 60 seconds to set up. Switch to My Library if you'd rather only see what you've saved.")) {
                        NavigationLink { MetadataSettingsView().toolbar(.visible, for: .navigationBar) } label: {
                            Text(DesktopInterfaceText.value("Open settings")).font(HarborTheme.font(13, weight: .semibold))
                        }.buttonStyle(HarborAccountButtonStyle(primary: true)).accessibilityIdentifier("calendar-open-settings")
                    }
                } else if shown.isEmpty && !model.loading && model.error == nil {
                    let empty = CalendarSources.emptyMonth(source: source, filter: kind, watchlistOnly: watchlistOnly, animeDub: animeDub)
                    CalendarEmptyCard(heading: DesktopInterfaceText.value(empty.heading), message: DesktopInterfaceText.value(empty.message, variables: empty.variables)) { EmptyView() }
                } else if daily.isEmpty && !model.loading {
                    Text(source == .library ? "No hay estrenos de tu biblioteca para este día." : "No hay estrenos para este día.").font(HarborTheme.font(14)).foregroundStyle(.secondary)
                }
            }.padding()
        }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink).environment(\.locale, interfaceLocale).navigationTitle("").toolbar(.hidden, for: .navigationBar)
            .task(id: loadID) { await model.load(month: month, app: app, source: source, animeDub: animeDub) }
            .sheet(isPresented: $showFilters) {
                CalendarFilterSheet(store: customCalendar, resultCount: shown.count, tmdbKey: MetadataPreferences.shared.tmdbKey, traktConnected: traktConnected)
            }
            .task(id: app.personalOwner) {
                customCalendar.reload()
                let trakt = TraktAccountStore.forOwner(app.personalOwner); if !trakt.ready { try? trakt.load() }
                let simkl = SimklAccountStore.forOwner(app.personalOwner); if !simkl.ready { try? simkl.load() }
            }
            .onChange(of: sourceRaw) { if source == .all && kind == "anime" { kind = "all" } }
    }
    private var monthGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 7) {
            ForEach(0..<7, id: \.self) { index in
                Text(calendar.shortStandaloneWeekdaySymbols[(calendar.firstWeekday - 1 + index) % 7].uppercased()).font(HarborTheme.font(10, weight: .semibold)).tracking(1).foregroundStyle(HarborTheme.ink.opacity(0.4))
            }
            ForEach(cells, id: \.self) { date in
                    let events = shown.filter { calendar.isDate($0.date, inSameDayAs: date) }
                    let inMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)
                    Button { selected = date; if !inMonth { month = date } } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(String(calendar.component(.day, from: date))).font(HarborTheme.font(12, weight: calendar.isDateInToday(date) ? .semibold : .medium))
                            Spacer(minLength: 0)
                            if let event = events.first {
                                Artwork(url: event.media.poster, maxPixels: 100).frame(width: large ? 23 : 18, height: large ? 30 : 23).clipShape(.rect(cornerRadius: 4))
                                if events.count > 1 { Text("+\(events.count - 1)").font(HarborTheme.font(9)).foregroundStyle(HarborTheme.accent) }
                            }
                        }.padding(6).frame(maxWidth: .infinity, alignment: .leading).frame(height: large ? 100 : 76).background(calendar.isDate(date, inSameDayAs: selected) ? Color.white.opacity(0.06) : HarborTheme.surface.opacity(0.2), in: .rect(cornerRadius: 10))
                            .overlay { RoundedRectangle(cornerRadius: 10).stroke(calendar.isDate(date, inSameDayAs: selected) ? Color.white.opacity(0.65) : .white.opacity(0.05), lineWidth: 1) }.opacity(inMonth ? 1 : 0.3).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(date.formatted(.dateTime.day().month().year().locale(interfaceLocale)) + ", \(events.count) estrenos")
                        .accessibilityIdentifier(inMonth ? "calendar-day-\(calendar.component(.day, from: date))" : "calendar-adjacent-day")
            }
        }
    }
    private func monthArrow(previous: Bool) -> some View {
        Image("desktop-chevron-right").resizable().scaledToFit().frame(width: 16, height: 16).rotationEffect(.degrees(previous ? 180 : 0)).foregroundStyle(HarborTheme.ink.opacity(0.6)).frame(width: 44, height: 44).background(HarborTheme.surface.opacity(0.2), in: .circle).overlay { Circle().stroke(HarborTheme.ink.opacity(0.05), lineWidth: 1) }
    }
    private func changeMonth(_ delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: month), let start = calendar.dateInterval(of: .month, for: next)?.start { month = next; selected = start }
    }
}

/// Desktop's empty month card (`views/calendar/empty-states.tsx`).
private struct CalendarEmptyCard<Action: View>: View {
    let heading: String
    let message: String
    let action: Action
    init(heading: String, message: String, @ViewBuilder action: () -> Action) {
        self.heading = heading; self.message = message; self.action = action()
    }
    var body: some View {
        VStack(spacing: 12) {
            Image("nav-calendar").resizable().scaledToFit().frame(width: 28, height: 28).foregroundStyle(HarborTheme.ink.opacity(0.4)).accessibilityHidden(true)
            Text(heading).font(HarborTheme.font(16, weight: .semibold)).multilineTextAlignment(.center)
            Text(message).font(HarborTheme.font(13.5)).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            action
        }.padding(.horizontal, 24).padding(.vertical, 36).frame(maxWidth: .infinity)
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(HarborTheme.ink.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [5, 4])) }
            .accessibilityElement(children: .contain).accessibilityIdentifier("calendar-empty-month")
    }
}
