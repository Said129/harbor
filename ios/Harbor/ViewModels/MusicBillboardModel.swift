import Foundation
import Observation

@MainActor @Observable final class MusicBillboardModel {
    let charts: [MusicBillboardReference]
    var chartID = "hot-100"
    var country = "all"
    var query = ""
    private(set) var ranking: MusicBillboardRanking?
    private(set) var loading = false
    private(set) var failure = false
    private(set) var busy: String?
    private(set) var unmatched: String?
    var opened: MusicCatalogItem?
    private var loadGeneration = UUID()
    private var openGeneration = UUID()
    init(charts: [MusicBillboardReference]? = nil) { self.charts = charts ?? (try? MusicBillboardAsset.read().charts) ?? [] }
    var chart: MusicBillboardReference? { charts.first { $0.id == chartID } }
    var available: [MusicBillboardReference] { charts.filter { country == "all" || $0.country == country } }
    func select(_ id: String) {
        guard charts.contains(where: { $0.id == id }) else { return }
        cancel(); chartID = id; query = ""; ranking = nil; failure = false; opened = nil
    }
    func selectCountry(_ code: String) {
        guard code == "all" || charts.contains(where: { $0.country == code }) else { return }
        country = code
        if code != "all", chart?.country != code, let next = available.first { select(next.id) }
    }
    func entries(locale: Locale) -> [MusicBillboardRanking.Entry] {
        let wanted = query.lowercased(with: locale)
        return ranking?.entries.filter { entry in
            let item = entry.item
            return (item.title + " " + (item.isArtist ? "" : item.subtitle ?? "")).lowercased(with: locale).contains(wanted)
        } ?? []
    }
    func load(client: any MusicBillboardCalling, refresh: Bool = false) async {
        guard !charts.isEmpty else { failure = true; return }
        if !refresh && ranking?.chartId == chartID { return }
        let token = UUID(), id = chartID; loadGeneration = token; openGeneration = UUID()
        ranking = nil; failure = false; busy = nil; unmatched = nil; loading = true
        defer { if loadGeneration == token { loading = false } }
        do {
            let value = try await client.ranking(id, refresh: refresh)
            try Task.checkCancellation(); guard loadGeneration == token, chartID == id else { return }
            guard value.chartId == id else { throw HarborError(code: "music-billboard-identity") }
            ranking = value
        } catch is CancellationError { return }
        catch { if loadGeneration == token { failure = true } }
    }
    func open(_ item: MusicCatalogItem, client: any MusicBillboardCalling, catalog: any MusicCatalogCalling) async {
        let token = UUID(); openGeneration = token; busy = item.id; unmatched = nil
        defer { if openGeneration == token { busy = nil } }
        do {
            let value = try await client.resolve(item, catalog: catalog)
            try Task.checkCancellation(); guard openGeneration == token else { return }
            if let value { opened = value } else { unmatched = item.id }
        } catch is CancellationError { return }
        catch { if openGeneration == token { unmatched = item.id } }
    }
    func cancel() { loadGeneration = UUID(); openGeneration = UUID(); loading = false; busy = nil }
}
