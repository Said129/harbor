import SwiftUI

struct SportsEventView: View {
    let event: SportsEvent
    let app: AppModel
    let preferences: SportsPreferences
    @State private var summary = SportsSummary()
    @State private var loading = false
    @State private var scheduled = false
    @State private var minutes = SportsRules.defaultReminderLead
    @State private var reminder = false
    @State private var error: String?
    @State private var table: SportsStandings?
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
                NavigationLink { LiveTVView(app: app, initialQuery: event.broadcasts.first ?? "") } label: { Label("Buscar canales en Live TV", image: "nav-livetv") }.buttonStyle(.bordered)
                ForEach(event.sides) { side in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text(side.name).font(.headline); Spacer(); Button { do { try preferences.toggle(side, league: event.league) } catch { self.error = safeMessage(error) } } label: { Image(systemName: preferences.favorite(side, league: event.league) ? "star.fill" : "star") }.accessibilityLabel("Favorito: \(side.name)") }
                        if let record = side.record { Text(record).font(.caption).foregroundStyle(.secondary) }
                        if !side.periods.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(side.periods) { period in
                                        VStack(spacing: 5) {
                                            Text(SportsPeriodHeading.label(group: event.league.group, leagueID: event.league.id, period: period.id)).font(.caption2).foregroundStyle(.secondary)
                                            Text(period.value).font(.subheadline.monospacedDigit())
                                        }
                                    }
                                }
                            }
                        }
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
                if !summary.timeline.isEmpty {
                    Text("Desarrollo del evento").font(.headline)
                    ForEach(summary.timeline) { entry in
                        HStack(alignment: .top, spacing: 10) {
                            Text(entry.clock).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
                            Image(systemName: symbol(entry.kind)).frame(width: 18).foregroundStyle(tint(entry.kind))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.text).font(.subheadline)
                                if let participant = entry.participant { Text(participant).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                } else if !summary.commentary.isEmpty {
                    Text("Desarrollo del evento").font(.headline)
                    ForEach(Array(summary.commentary.enumerated()), id: \.offset) { _, text in Text(text).font(.subheadline).foregroundStyle(.secondary) }
                }
                if let group = highlightedGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Clasificación").font(.headline)
                        Text(group.title).font(.caption).foregroundStyle(.secondary)
                        ForEach(group.rows) { row in
                            let highlighted = sideIDs.contains(row.side.id)
                            HStack(spacing: 10) {
                                Text("\(row.rank)").font(.caption.monospacedDigit()).frame(width: 26, alignment: .leading)
                                Text(row.side.name).font(.caption.weight(highlighted ? .bold : .regular)).lineLimit(1)
                                Spacer()
                                Text(row.value(["points"])).font(.caption.monospacedDigit().weight(.bold))
                            }.padding(8).background(highlighted ? HarborTheme.surface : Color.clear, in: .rect(cornerRadius: 8))
                        }
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(HarborTheme.surface, in: .rect(cornerRadius: 12))
                }
                if let raw = event.link, let url = URL(string: raw) { Link("Evento en ESPN", destination: url) }
            }.padding(16)
        }.background(HarborTheme.background).navigationTitle(event.league.title).navigationBarTitleDisplayMode(.inline)
            .task { scheduled = await SportsReminderService.shared.scheduled(event, owner: preferences.owner); await load(); table = try? await SportsStandingsService.shared.table(event.league) }
            .refreshable { await load() }
            .sheet(isPresented: $reminder) {
                NavigationStack {
                    Form {
                        Text(event.title).font(.headline)
                        Picker("Avisarme", selection: $minutes) { ForEach(SportsRules.reminderLeads, id: \.self) { lead in Text(leadLabel(lead)).tag(lead) } }
                        Button("Guardar recordatorio") {
                            Task { do { try await SportsReminderService.shared.schedule(event, owner: preferences.owner, minutes: minutes); scheduled = true; reminder = false } catch { self.error = safeMessage(error); reminder = false } }
                        }
                    }.navigationTitle("Recordatorio").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cancelar") { reminder = false } } }
                }
            }
    }
    private var sideIDs: Set<String> { Set(event.sides.map(\.id)) }
    /// The standings group that holds both teams, else the first group that holds either.
    private var highlightedGroup: SportsStandingGroup? {
        let groups = table?.groups ?? []
        let ids = sideIDs
        return groups.first { group in ids.isSubset(of: Set(group.rows.map { $0.side.id })) } ?? groups.first { group in group.rows.contains { ids.contains($0.side.id) } }
    }
    private func leadLabel(_ lead: Int) -> String {
        lead == 1440 ? DesktopInterfaceText.value("1 day before") : DesktopInterfaceText.value("{n} minutes before", variables: ["n": String(lead)])
    }
    private func symbol(_ kind: SportsTimelineKind) -> String {
        switch kind {
        case .goal: return "soccerball"
        case .yellowCard, .redCard: return "rectangle.portrait.fill"
        case .substitution: return "arrow.left.arrow.right"
        case .other: return "circle.fill"
        }
    }
    private func tint(_ kind: SportsTimelineKind) -> Color {
        switch kind {
        case .yellowCard: return .yellow
        case .redCard: return .red
        default: return .secondary
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
