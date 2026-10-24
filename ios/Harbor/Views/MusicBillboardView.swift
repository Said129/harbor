import SwiftUI

@MainActor struct MusicBillboardView: View {
    @Environment(\.musicArtistMetadata) private var artistMetadata
    let client: any MusicBillboardCalling
    let catalog: any MusicCatalogCalling
    @State private var model = MusicBillboardModel()
    @State private var revision = 0
    @State private var operation: Task<Void, Never>?
    @FocusState private var searching: Bool
    @AppStorage("uiLanguage") private var language = "en"
    private var locale: Locale { Locale(identifier: InterfaceLanguage.resolve(language)) }
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    heading.id("billboard-top")
                    controls
                    if let chart = model.chart {
                        Text(chart.name).font(.title2.bold()).accessibilityIdentifier("music-billboard-title")
                    }
                    if let ranking = model.ranking {
                        Text(publication(ranking)).font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("music-billboard-date")
                    }
                    if model.loading { ProgressView(text("music.loading")).frame(maxWidth: .infinity).accessibilityIdentifier("music-billboard-loading") }
                    if model.failure {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(text("music.billboard.unavailable")).foregroundStyle(.secondary)
                            Button(text("common.retry")) { revision += 1 }.buttonStyle(.bordered).accessibilityIdentifier("music-billboard-retry")
                            if let url = model.chart?.url { Link("billboard.com", destination: url) }
                        }.accessibilityElement(children: .contain).accessibilityIdentifier("music-billboard-error")
                    }
                    ForEach(model.entries(locale: locale)) { entry in row(entry) }
                    if model.ranking != nil, model.entries(locale: locale).isEmpty {
                        Text(text("No results")).foregroundStyle(.secondary).accessibilityIdentifier("music-billboard-empty")
                    }
                }.padding(18).padding(.bottom, 30).frame(maxWidth: 1000).frame(maxWidth: .infinity)
            }.accessibilityIdentifier("music-billboard-scroll").scrollDismissesKeyboard(.interactively)
                .onChange(of: model.chartID) { _, _ in proxy.scrollTo("billboard-top", anchor: .top) }
                .refreshable { await model.load(client: client, refresh: true) }
        }.background(HarborTheme.background).navigationTitle("Billboard").navigationBarTitleDisplayMode(.inline)
            .task(id: model.chartID + "|" + String(revision)) { await model.load(client: client, refresh: revision > 0) }
            .navigationDestination(item: $model.opened) { item in MusicCatalogDetailView(item: item, client: catalog).environment(\.musicArtistMetadata, artistMetadata) }
            .onDisappear { operation?.cancel(); model.cancel() }
    }
    private var heading: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Billboard").font(.largeTitle.bold())
                Text(text("music.row.charts")).foregroundStyle(.secondary)
            }
            Spacer()
            if let url = model.chart?.url { Link(destination: url) { Image(systemName: "arrow.up.right").frame(width: 44, height: 44) }.accessibilityLabel("billboard.com") }
        }
    }
    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(text("music.billboard.country"), selection: Binding(get: { model.country }, set: { model.selectCountry($0) })) {
                Text(text("music.filter.all")).tag("all")
                ForEach(Array(Set(model.charts.map(\.country))).sorted { countryName($0).localizedStandardCompare(countryName($1)) == .orderedAscending }, id: \.self) { code in
                    Text(countryName(code)).tag(code)
                }
            }.accessibilityIdentifier("music-billboard-country")
            Picker(text("music.row.charts"), selection: Binding(get: { model.chartID }, set: { model.select($0) })) {
                ForEach(model.available) { chart in Text(chart.name).tag(chart.id) }
            }.accessibilityIdentifier("music-billboard-chart")
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(text("music.filter.tracks"), text: $model.query).submitLabel(.search).textInputAutocapitalization(.never)
                    .focused($searching).onSubmit { searching = false }
                    .accessibilityIdentifier("music-billboard-search")
                if !model.query.isEmpty { Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel(text("Clear search")).accessibilityIdentifier("music-billboard-clear-search") }
            }.padding(12).background(HarborTheme.surface, in: .rect(cornerRadius: 12))
        }.tint(HarborTheme.ink)
    }
    private func row(_ entry: MusicBillboardRanking.Entry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(String(format: "%02d", entry.rank)).font(.title3.monospacedDigit()).foregroundStyle(.secondary).frame(minWidth: 30).padding(.top, 12)
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    operation?.cancel(); operation = Task { await model.open(entry.item, client: client, catalog: catalog) }
                } label: { MusicCatalogCompactItem(item: entry.item) }
                    .buttonStyle(.plain).disabled(model.busy == entry.item.id).accessibilityIdentifier("music-billboard-entry-" + String(entry.rank))
                if model.unmatched == entry.item.id { Text(text("music.billboard.match")).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("music-billboard-unmatched") }
            }
            Spacer(minLength: 0)
            if model.busy == entry.item.id { ProgressView().controlSize(.small).padding(.top, 12) }
            if let url = model.ranking?.sourceURL {
                Link(destination: url) { Image(systemName: "arrow.up.right").frame(width: 44, height: 44) }.accessibilityLabel(text("music.billboard.source"))
            }
        }.padding(.vertical, 4).contextMenu {
            if let url = model.ranking?.sourceURL { Link(text("music.billboard.source"), destination: url) }
        }
    }
    private func countryName(_ code: String) -> String {
        if code == "global" { return text("music.billboard.world") }
        if code == "arabic" { return locale.localizedString(forLanguageCode: "ar") ?? "Arabic" }
        return locale.localizedString(forRegionCode: code) ?? code
    }
    private func publication(_ ranking: MusicBillboardRanking) -> String {
        let date = ranking.dateValue?.formatted(.dateTime.day().month(.wide).year().locale(locale)) ?? ranking.date
        return date + " · " + String(ranking.entries.count)
    }
}
