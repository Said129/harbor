import SwiftUI

struct SportsEventView: View {
    let event: SportsEvent
    let app: AppModel
    let preferences: SportsPreferences
    @State private var summary = SportsSummary()
    @State private var loading = false
    @State private var scheduled = false
    @State private var minutes = 10
    @State private var reminder = false
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SportsEventCard(event: event)
                HStack {
                    Label { Text(event.date, format: .dateTime.day().month().hour().minute()) } icon: { Image("ui-remindme").resizable().scaledToFit().frame(width: 20, height: 20) }
                    Spacer()
                    if event.state == "pre" { Button(scheduled ? "Cancelar aviso" : "Recordarme") { if scheduled { Task { await SportsReminderService.shared.cancel(event, owner: preferences.owner); scheduled = false } } else { reminder = true } }.font(.caption) }
                }
                if !event.venue.isEmpty { Label(event.venue, systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(.secondary) }
                if !event.broadcasts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) { Text("Dónde se emite").font(.headline); Text(event.broadcasts.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary) }
                }
                NavigationLink { SearchView(app: app, initialQuery: event.sides.count == 2 ? event.sides[0].name : event.title) } label: { Label("Buscar en mis addons", image: "nav-search") }.buttonStyle(.bordered)
                ForEach(event.sides) { side in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text(side.name).font(.headline); Spacer(); Button { do { try preferences.toggle(side, league: event.league) } catch { self.error = safeMessage(error) } } label: { Image(systemName: preferences.favorite(side, league: event.league) ? "star.fill" : "star") }.accessibilityLabel("Favorito: \(side.name)") }
                        if let record = side.record { Text(record).font(.caption).foregroundStyle(.secondary) }
                        if !side.periods.isEmpty { HStack(spacing: 16) { ForEach(side.periods) { period in VStack(spacing: 5) { Text("\(period.id)").font(.caption2).foregroundStyle(.secondary); Text(period.value).font(.subheadline.monospacedDigit()) } } }
                    }.padding(14).background(HarborTheme.surface, in: .rect(cornerRadius: 12))
                }
                if loading { ProgressView().frame(maxWidth: .infinity) }
                if let error { Text(error).font(.caption).foregroundStyle(.orange); Button("Reintentar estadísticas") { Task { await load() } } }
                ForEach(summary.groups) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(group.title).font(.headline)
                        ForEach(group.values) { value in VStack(alignment: .leading, spacing: 5) { Text(value.title).font(.subheadline.weight(.medium)); Text(value.value).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) } }
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(HarborTheme.surface, in: .rect(cornerRadius: 12))
                }
                if !summary.commentary.isEmpty {
                    Text("Desarrollo del evento").font(.headline)
                    ForEach(Array(summary.commentary.enumerated()), id: \.offset) { _, text in Text(text).font(.subheadline).foregroundStyle(.secondary) }
                }
                if let raw = event.link, let url = URL(string: raw) { Link("Evento en ESPN", destination: url) }
            }.padding(16)
        }.background(HarborTheme.background).navigationTitle(event.league.title).navigationBarTitleDisplayMode(.inline)
            .task { scheduled = await SportsReminderService.shared.scheduled(event, owner: preferences.owner); await load() }
            .refreshable { await load() }
            .sheet(isPresented: $reminder) {
                NavigationStack {
                    Form {
                        Text(event.title).font(.headline)
                        Picker("Avisarme", selection: $minutes) { Text("Al empezar").tag(0); Text("5 minutos antes").tag(5); Text("10 minutos antes").tag(10); Text("15 minutos antes").tag(15); Text("30 minutos antes").tag(30) }
                        Button("Guardar recordatorio") {
                            Task { do { try await SportsReminderService.shared.schedule(event, owner: preferences.owner, minutes: minutes); scheduled = true; reminder = false } catch { self.error = safeMessage(error); reminder = false } }
                        }
                    }.navigationTitle("Recordatorio").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cancelar") { reminder = false } } }
                }
            }
    }
    private func load() async {
        guard !loading else { return }
        loading = true; error = nil; defer { loading = false }
        do { summary = try await SportsService.shared.summary(event) }
        catch is CancellationError { return }
        catch { self.error = "No se pudieron actualizar las estadísticas. Los datos del evento siguen disponibles." }
    }
}
