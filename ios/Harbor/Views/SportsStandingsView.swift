import SwiftUI

private struct StandingColumn: Identifiable {
    let id: String
    let names: [String]
    let label: String
    var emphasized = false
    static func columns(_ sport: String) -> [Self] {
        let played = Self(id: "played", names: ["gamesPlayed", "matchesPlayed"], label: "PJ")
        let wins = Self(id: "wins", names: ["wins", "gamesWon", "matchesWon"], label: "G")
        let draws = Self(id: "draws", names: ["ties", "gamesDrawn", "tiegames", "matchesDraw", "matchesTied"], label: "E")
        let losses = Self(id: "losses", names: ["losses", "gamesLost", "matchesLost"], label: "P")
        let percent = Self(id: "percent", names: ["winPercent", "percentage"], label: "%")
        let points = Self(id: "points", names: ["points", "matchPoints", "championshipPts"], label: "PTS", emphasized: true)
        let difference = Self(id: "difference", names: ["pointsDifference", "pointDifferential"], label: "DIF")
        switch sport {
        case "basketball", "baseball": return [wins, losses, percent, Self(id: "behind", names: ["gamesBehind"], label: "GB")]
        case "football": return [wins, losses, draws, percent]
        case "hockey": return [played, wins, losses, Self(id: "overtime", names: ["otLosses", "overtimeLosses", "OTLosses"], label: "OTL"), points]
        case "lacrosse": return [wins, losses, percent]
        case "aussie": return [played, wins, losses, draws, percent, points]
        case "rugby": return [played, wins, draws, losses, difference, points]
        case "cricket": return [played, wins, losses, Self(id: "noresult", names: ["noresult"], label: "NR"), Self(id: "runrate", names: ["netrr"], label: "NRR"), points]
        case "motorsport": return [points]
        default: return [played, wins, draws, losses, difference, points]
        }
    }
}

struct SportsStandingsView: View {
    let league: SportsLeague
    let preferences: SportsPreferences
    @State private var table: SportsStandings?
    @State private var selected = ""
    @State private var loading = false
    @State private var error: String?
    private var group: SportsStandingGroup? { table?.groups.first { $0.id == selected } ?? table?.groups.first }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    if let logo = league.logo { Artwork(url: logo, fit: .fit, maxPixels: 200).frame(width: 42, height: 42) }
                    VStack(alignment: .leading, spacing: 4) { Text(table?.title ?? league.title).font(.headline); if let season = table?.season { Text(season).font(.caption).foregroundStyle(.secondary) } }
                }
                if loading { ProgressView("Cargando clasificación…").frame(maxWidth: .infinity) }
                if let error { Text(error).font(.caption).foregroundStyle(.orange); Button("Reintentar") { Task { await load(refresh: true) } } }
                if let table {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(table.groups) { group in
                                Button { selected = group.id } label: { Text(group.title).font(.caption.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 10).foregroundStyle(self.group?.id == group.id ? HarborTheme.background : HarborTheme.ink).background(self.group?.id == group.id ? HarborTheme.ink : HarborTheme.surface, in: .capsule) }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                if let group {
                    let columns = StandingColumn.columns(league.group).filter { col in group.rows.contains { !$0.value(col.names).isEmpty } }
                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(spacing: 0) {
                            HStack(spacing: 8) { Text("#").frame(width: 24); Text("Equipo / atleta").frame(width: 170, alignment: .leading); ForEach(columns) { col in Text(col.label).frame(width: 48, alignment: .trailing) } }.font(.caption2.bold()).foregroundStyle(.secondary).padding(12)
                            ForEach(group.rows) { row in
                                HStack(spacing: 8) {
                                    Text("\(row.rank)").font(.caption.monospacedDigit()).frame(width: 24)
                                    HStack(spacing: 8) {
                                        if let logo = row.side.logo { Artwork(url: logo, fit: .fit, maxPixels: 100).frame(width: 24, height: 24) }
                                        Text(row.side.name).font(.caption.weight(preferences.favorite(row.side, league: league) ? .semibold : .regular)).lineLimit(2)
                                    }.frame(width: 170, alignment: .leading)
                                    ForEach(columns) { col in Text(row.value(col.names)).font(.caption.weight(col.emphasized ? .bold : .regular)).monospacedDigit().frame(width: 48, alignment: .trailing) }
                                }.padding(12).background(preferences.favorite(row.side, league: league) ? HarborTheme.surface : .clear)
                                    .contextMenu {
                                        Button(preferences.favorite(row.side, league: league) ? "Quitar de favoritos" : "Añadir a favoritos") { do { try preferences.toggle(row.side, league: league) } catch { self.error = safeMessage(error) } }
                                    }
                                if !row.note.isEmpty { Text(row.note).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.bottom, 6) }
                                Divider().opacity(0.25)
                            }
                        }.background(HarborTheme.surface.opacity(0.35), in: .rect(cornerRadius: 12))
                    }
                    Text("Mantén pulsado un equipo para cambiar tus favoritos.").font(.caption2).foregroundStyle(.secondary)
                }
                Text("Clasificación publicada por ESPN").font(.caption2).foregroundStyle(.secondary)
            }.padding(16)
        }.background(HarborTheme.background).navigationTitle("Clasificación").navigationBarTitleDisplayMode(.inline)
            .task(id: league.id) { await load(refresh: false) }
            .refreshable { await load(refresh: true) }
    }
    private func load(refresh: Bool) async {
        guard !loading else { return }
        loading = true; error = nil; defer { loading = false }
        do { table = try await SportsStandingsService.shared.table(league, refresh: refresh) }
        catch is CancellationError { return }
        catch { if table == nil { table = await SportsStandingsService.shared.saved(league, season: nil) }; self.error = "No se pudo actualizar la clasificación. Vuelve a intentarlo." }
    }
}
