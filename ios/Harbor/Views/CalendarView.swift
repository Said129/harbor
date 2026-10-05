import SwiftUI

struct CalendarView: View {
    let app: AppModel
    @State private var model = CalendarModel()
    @State private var month = Date()
    @State private var selected = Date()
    @State private var kind = "all"
    private let calendar = Calendar.current
    private var shown: [ReleaseEvent] { model.events.filter { kind == "all" || $0.media.type == kind } }
    private var daily: [ReleaseEvent] { shown.filter { calendar.isDate($0.date, inSameDayAs: selected) } }
    private var cells: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month), let days = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let offset = (calendar.component(.weekday, from: interval.start) - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: offset) + days.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: interval.start) }.map(Optional.some)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Button { changeMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("Mes anterior")
                    Spacer()
                    Text(month.formatted(.dateTime.month(.wide).year())).font(.title3.bold())
                    Spacer()
                    Button { changeMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel("Mes siguiente")
                }
                HStack { Text(app.user == nil ? "Biblioteca local" : "Biblioteca de Stremio").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Hoy") { month = Date(); selected = Date() }.font(.caption) }
                Picker("Contenido", selection: $kind) { Text("Todo").tag("all"); Text("Películas").tag("movie"); Text("Series").tag("series"); Text("Anime").tag("anime") }.pickerStyle(.segmented)
                monthGrid
                if model.loading { ProgressView("Recuperando fechas…").frame(maxWidth: .infinity) }
                if let error = model.error { Text(error).font(.caption).foregroundStyle(.orange); Button("Reintentar") { Task { await model.load(month: month, app: app) } } }
                Text(selected.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.headline)
                ForEach(daily) { event in
                    NavigationLink(value: event.media) {
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
        }.background(HarborTheme.background).navigationTitle("Calendario").navigationBarTitleDisplayMode(.inline)
            .task(id: "\(calendar.component(.year, from: month))-\(calendar.component(.month, from: month))|\(app.library.items.map { $0.id + $0.modified }.joined())") { await model.load(month: month, app: app) }
    }
    private var monthGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 7) {
            ForEach(0..<7, id: \.self) { index in
                Text(calendar.veryShortStandaloneWeekdaySymbols[(calendar.firstWeekday - 1 + index) % 7]).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                if let date {
                    Button { selected = date } label: {
                        VStack(spacing: 4) {
                            Text(String(calendar.component(.day, from: date))).font(.subheadline.weight(calendar.isDateInToday(date) ? .bold : .regular))
                            Circle().fill(shown.contains { calendar.isDate($0.date, inSameDayAs: date) } ? HarborTheme.accent : .clear).frame(width: 4, height: 4)
                        }.frame(maxWidth: .infinity).frame(height: 43).background(calendar.isDate(date, inSameDayAs: selected) ? Color.white.opacity(0.12) : .clear, in: .rect(cornerRadius: 8))
                    }.buttonStyle(.plain).accessibilityLabel(date.formatted(.dateTime.day().month().year()))
                } else { Color.clear.frame(height: 43) }
            }
        }
    }
    private func changeMonth(_ delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: month), let start = calendar.dateInterval(of: .month, for: next)?.start { month = next; selected = start }
    }
}
