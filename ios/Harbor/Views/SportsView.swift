import SwiftUI

private struct SportsConsent: Codable {
    let version: Int
    let status: String
    let acceptedAt: Date?
}

struct SportsView: View {
    let app: AppModel
    @State private var preferences: SportsPreferences
    @State private var leagues: [SportsLeague] = []
    @State private var events: [SportsEvent] = []
    @State private var date = Date()
    @State private var state = "all"
    @State private var sport = "all"
    @State private var onlyFavorites = false
    @State private var configuring = false
    @State private var loading = false
    @State private var error: String?
    @State private var generation = UUID()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("harbor-sports-consent") private var consent = ""
    @MainActor init(app: AppModel) { self.app = app; _preferences = State(initialValue: SportsPreferences(owner: app.user?.id ?? "guest")) }
    private var accepted: Bool { guard let data = consent.data(using: .utf8), let receipt = try? JSONDecoder().decode(SportsConsent.self, from: data) else { return false }; return receipt.version == 1 && receipt.status == "accepted" && receipt.acceptedAt != nil }
    private var day: String { let parts = Calendar.current.dateComponents([.year, .month, .day], from: date); return String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0) }
    private var signature: String { day + "|" + preferences.leagues.joined(separator: ",") + "|" + String(accepted) }
    private var filtered: [SportsEvent] { events.filter { event in (state == "all" || event.state == state) && (sport == "all" || event.league.group == sport) && (!onlyFavorites || event.sides.contains(where: { preferences.favorite($0, league: event.league) })) } }
    var body: some View {
        Group {
            if accepted { board }
            else { usageNotice }
        }.background(HarborTheme.background).navigationTitle("Sports").navigationBarTitleDisplayMode(.inline)
            .toolbar { if accepted { ToolbarItem(placement: .topBarTrailing) { Button { configuring = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Configurar Sports") } } }
            .task {
                do { leagues = try SportsLeague.catalog() } catch { self.error = safeMessage(error) }
                if accepted { await load(refresh: false) }
            }
            .task(id: signature) { if accepted, !leagues.isEmpty { await load(refresh: false) } else if !accepted { generation = UUID(); events = []; loading = false } }
            .task(id: signature + "|" + String(describing: scenePhase)) {
                guard accepted, scenePhase == .active else { return }
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(Calendar.current.isDateInToday(date) ? 30 : 120)) } catch { return }
                    guard scenePhase == .active, accepted, !Task.isCancelled else { return }
                    if !loading { await load(refresh: true) }
                }
            }
            .sheet(isPresented: $configuring) { SportsSettingsView(leagues: leagues, preferences: preferences, onRevoke: { acknowledge(false); configuring = false }) }
    }
    private var board: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 40, height: 40) }.accessibilityLabel("Día anterior")
                    DatePicker("Fecha", selection: $date, displayedComponents: .date).labelsHidden()
                    Spacer(); Button("Hoy") { date = Date() }
                    Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 40, height: 40) }.accessibilityLabel("Día siguiente")
                }
                Picker("Estado", selection: $state) { Text("Todos").tag("all"); Text("En directo").tag("in"); Text("Próximos").tag("pre"); Text("Resultados").tag("post") }.pickerStyle(.segmented)
                HStack {
                    Picker("Deporte", selection: $sport) { Text("Todos los deportes").tag("all"); ForEach(Array(Set(events.map { $0.league.group })).sorted(), id: \.self) { Text(sportName($0)).tag($0) } }
                    Spacer(); Toggle("Favoritos", isOn: $onlyFavorites).font(.caption).fixedSize()
                }
                if !preferences.leagues.isEmpty {
                    Menu {
                        ForEach(leagues.filter { preferences.leagues.contains($0.id) }) { league in NavigationLink(league.title) { SportsStandingsView(league: league, preferences: preferences) } }
                    } label: { Label("Clasificaciones", systemImage: "list.number") }.font(.subheadline)
                }
                if let error = error ?? preferences.error { Text(error).font(.caption).foregroundStyle(.orange) }
                if loading { ProgressView("Cargando Sports…").frame(maxWidth: .infinity).padding() }
                ForEach(filtered) { event in
                    NavigationLink { SportsEventView(event: event, app: app, preferences: preferences) } label: { SportsEventCard(event: event, compact: true) }.buttonStyle(.plain)
                }
                if filtered.isEmpty && !loading { ContentUnavailableView("Sin eventos", image: "nav-sports", description: Text(preferences.leagues.isEmpty ? "Selecciona tus ligas en las opciones de Sports." : "No hay eventos publicados para esta fecha y estos filtros.")) }
                Text("Horarios y resultados de ESPN · Hora local").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }.padding(16)
        }.refreshable { await load(refresh: true) }
    }
    private var usageNotice: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image("nav-sports").resizable().scaledToFit().frame(width: 44, height: 44)
                Text("Sports en Harbor").font(.title2.bold())
                Text("Harbor muestra metadata de servicios externos. No aloja retransmisiones ni proporciona suscripciones deportivas.")
                Text("Los horarios, resultados, estadísticas e imágenes proceden de terceros y se guardan temporalmente en este dispositivo. Al abrir Sports, esos servicios reciben las solicitudes de conexión.").foregroundStyle(.secondary)
                Text("Utiliza fuentes que tengas permiso para ver. Las coincidencias con tus canales no garantizan disponibilidad ni derechos de acceso.").foregroundStyle(.secondary)
                Link("Condiciones del servicio ESPN", destination: URL(string: "https://disneytermsofuse.com/english/")!)
                if let error { Text(error).foregroundStyle(.orange) }
                Button("Aceptar y abrir Sports") { acknowledge(true) }.buttonStyle(.borderedProminent)
                Button("Ahora no") { acknowledge(false) }
            }.padding(24)
        }
    }
    private func acknowledge(_ accepted: Bool) {
        let receipt = SportsConsent(version: 1, status: accepted ? "accepted" : "declined", acceptedAt: accepted ? Date() : nil)
        if let data = try? JSONEncoder().encode(receipt), let text = String(data: data, encoding: .utf8) { consent = text }
    }
    private func shift(_ amount: Int) { if let shifted = Calendar.current.date(byAdding: .day, value: amount, to: date) { date = shifted } }
    private func load(refresh: Bool) async {
        guard accepted else { return }
        let token = UUID(); generation = token; loading = true; error = nil
        let stamp = day, selected = leagues.filter { preferences.leagues.contains($0.id) }
        defer { if generation == token { loading = false } }
        let results = await withTaskGroup(of: ([SportsEvent], Bool).self, returning: [([SportsEvent], Bool)].self) { group in
            var iterator = selected.makeIterator(), output: [([SportsEvent], Bool)] = []
            func submit(_ league: SportsLeague) {
                group.addTask {
                    do { return (try await SportsService.shared.events(league, date: stamp, refresh: refresh), false) }
                    catch { return (await SportsService.shared.savedEvents(league, date: stamp) ?? [], true) }
                }
            }
            for _ in 0..<4 { if let league = iterator.next() { submit(league) } }
            for await value in group { output.append(value); if !Task.isCancelled, let league = iterator.next() { submit(league) } }
            return output
        }
        guard generation == token, !Task.isCancelled, accepted else { return }
        let loaded = results.flatMap { $0.0 }
        if !loaded.isEmpty || !results.contains(where: { $0.1 }) || events.first.map({ Calendar.current.isDate($0.date, inSameDayAs: date) }) != true { events = loaded }
        if results.contains(where: { $0.1 }) && loaded.isEmpty { error = "No se pudieron actualizar las ligas seleccionadas. Vuelve a intentarlo." }
    }
}

struct SportsEventCard: View {
    let event: SportsEvent
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(event.league.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary); Spacer(); if event.state == "in" { Text("LIVE").font(.caption2.bold()).foregroundStyle(.red) } else { Text(event.date, style: .time).font(.caption.monospacedDigit()).foregroundStyle(.secondary) } }
            if event.sides.count > 2 { Text(event.title).font(.headline) }
            ForEach(compact ? Array(event.sides.prefix(4)) : event.sides) { side in
                HStack(spacing: 12) {
                    if let logo = side.logo { Artwork(url: logo, fit: .fit, maxPixels: 180).frame(width: 34, height: 34).clipShape(.circle) }
                    else { Image(systemName: "person.crop.circle").font(.title2).frame(width: 34, height: 34).foregroundStyle(.secondary) }
                    Text(side.name).font(.subheadline.weight(side.winner ? .bold : .medium)).lineLimit(2)
                    Spacer()
                    if let score = side.score { Text(score).font(.title3.bold()).monospacedDigit() }
                }
            }
            Text(event.status).font(.caption).foregroundStyle(.secondary)
        }.padding(16).background(HarborTheme.surface, in: .rect(cornerRadius: 14))
    }
}

private struct SportsSettingsView: View {
    let leagues: [SportsLeague]
    let preferences: SportsPreferences
    let onRevoke: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Section("Tus ligas") {
                    ForEach(leagues.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || sportName($0.group).localizedCaseInsensitiveContains(query) }) { league in
                        Toggle(isOn: Binding(get: { preferences.leagues.contains(league.id) }, set: { selected in do { var ids = preferences.leagues.filter { $0 != league.id }; if selected { ids.append(league.id) }; try preferences.setLeagues(ids) } catch { self.error = safeMessage(error) } })) { VStack(alignment: .leading, spacing: 4) { Text(league.title); Text(sportName(league.group)).font(.caption).foregroundStyle(.secondary) } }.disabled(!preferences.ready)
                    }
                }
                if let error { Text(error).foregroundStyle(.orange) }
                Section { Button("Revocar acceso a servicios deportivos", role: .destructive, action: onRevoke) }
            }.navigationTitle("Configurar Sports").searchable(text: $query, prompt: "Ligas y deportes").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Listo") { dismiss() } } }
        }
    }
}

private func sportName(_ id: String) -> String {
    ["soccer": "Fútbol", "basketball": "Baloncesto", "football": "Fútbol americano", "baseball": "Béisbol", "hockey": "Hockey", "combat": "Combate", "motorsport": "Motor", "tennis": "Tenis", "golf": "Golf", "rugby": "Rugby", "cricket": "Críquet", "volleyball": "Voleibol" ][id] ?? id.capitalized
}
