import SwiftUI

struct CalendarView: View {
    let app: AppModel
    @State private var model = CalendarModel()
    @State private var month = Date()
    @State private var selected = Date()
    @State private var kind = "all"
    @AppStorage("calendar.monday") private var monday = false
    @AppStorage("calendar.large") private var large = false
    private var calendar: Calendar { var calendar = Calendar.current; calendar.firstWeekday = monday ? 2 : 1; return calendar }
    private var shown: [ReleaseEvent] { model.events.filter { kind == "all" || $0.media.type == kind } }
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
                    Button { changeMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("Mes anterior")
                    Spacer()
                    Text(month.formatted(.dateTime.month(.wide).year())).font(.subheadline.bold()).padding(.horizontal, 16).frame(minHeight: 40).background(HarborTheme.surface.opacity(0.5), in: .capsule)
                    Spacer()
                    Button { changeMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel("Mes siguiente")
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        HarborPill(title: "Hoy") { month = Date(); selected = Date() }
                        HarborPill(title: "Mi biblioteca", selected: kind == "all", icon: "nav-library") { kind = "all" }
                        HarborPill(title: "Películas", selected: kind == "movie", icon: "nav-movies") { kind = "movie" }
                        HarborPill(title: "Series", selected: kind == "series", icon: "nav-shows") { kind = "series" }
                        HarborPill(title: "Anime", selected: kind == "anime", icon: "nav-anime") { kind = "anime" }
                    }
                }.scrollIndicators(.hidden)
                ScrollView(.horizontal) { HStack(spacing: 6) { HarborPill(title: "Empezar en lunes", selected: monday) { monday.toggle() }; HarborPill(title: "Normal", selected: !large) { large = false }; HarborPill(title: "Grande", selected: large) { large = true } } }.scrollIndicators(.hidden)
                monthGrid
                if model.loading { ProgressView("Recuperando fechas…").frame(maxWidth: .infinity) }
                if let error = model.error { Text(error).font(.caption).foregroundStyle(.orange); Button("Reintentar") { Task { await model.load(month: month, app: app) } } }
                Text(selected.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.headline)
                ForEach(daily) { event in
                    NavigationLink { DetailView(media: event.media, app: app) } label: {
                        HStack(alignment: .top, spacing: 14) {
                            Artwork(url: event.media.poster, maxPixels: 240).frame(width: 64, height: 96).clipShape(.rect(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 8) {
                                Text(event.media.name).font(.headline)
                                if let episode = event.episode { Text("T\(episode.season ?? 0) · E\(episode.episode ?? 0) · \(episode.name ?? episode.title ?? "")").font(.caption).foregroundStyle(.secondary) }
                                Text(event.date, style: .time).font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.buttonStyle(.plain)
                }
                if daily.isEmpty && !model.loading { Text("No hay estrenos de tu biblioteca para este día.").font(.subheadline).foregroundStyle(.secondary) }
            }.padding()
        }.background(HarborTheme.background).navigationTitle("").toolbar(.hidden, for: .navigationBar)
            .task(id: "\(app.library.owner)|\(calendar.component(.year, from: month))-\(calendar.component(.month, from: month))|\(app.library.items.map { $0.id + $0.modified }.joined())") { await model.load(month: month, app: app) }
    }
    private var monthGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 7) {
            ForEach(0..<7, id: \.self) { index in
                Text(calendar.veryShortStandaloneWeekdaySymbols[(calendar.firstWeekday - 1 + index) % 7]).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(cells, id: \.self) { date in
                    let events = shown.filter { calendar.isDate($0.date, inSameDayAs: date) }
                    let inMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)
                    Button { selected = date; if !inMonth { month = date } } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(String(calendar.component(.day, from: date))).font(.subheadline.weight(calendar.isDateInToday(date) ? .bold : .regular))
                            Spacer(minLength: 0)
                            if let event = events.first {
                                Artwork(url: event.media.poster, maxPixels: 100).frame(width: large ? 23 : 18, height: large ? 30 : 23).clipShape(.rect(cornerRadius: 4))
                                if events.count > 1 { Text("+\(events.count - 1)").font(.system(size: 8)).foregroundStyle(HarborTheme.accent) }
                            }
                        }.padding(6).frame(maxWidth: .infinity, alignment: .leading).frame(height: large ? 100 : 76).background(calendar.isDate(date, inSameDayAs: selected) ? Color.white.opacity(0.06) : HarborTheme.surface.opacity(0.2), in: .rect(cornerRadius: 10))
                            .overlay { RoundedRectangle(cornerRadius: 10).stroke(calendar.isDate(date, inSameDayAs: selected) ? Color.white.opacity(0.65) : .white.opacity(0.05), lineWidth: 1) }.opacity(inMonth ? 1 : 0.3).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(date.formatted(.dateTime.day().month().year()) + ", \(events.count) estrenos")
                        .accessibilityIdentifier(inMonth ? "calendar-day-\(calendar.component(.day, from: date))" : "calendar-adjacent-day")
            }
        }
    }
    private func changeMonth(_ delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: month), let start = calendar.dateInterval(of: .month, for: next)?.start { month = next; selected = start }
    }
}
