import SwiftUI

struct TraktLibraryContent: View {
    let app: AppModel
    let model: TraktLibraryModel
    var metadata: (@MainActor (Media) async throws -> Media)? = nil
    @State private var kind = LibraryKind.all
    @State private var query = ""
    private func text(_ key: String, variables: [String: String] = [:]) -> String { DesktopInterfaceText.value(key, variables: variables) }
    var body: some View {
        let combined = model.watchlist + model.history
        VStack(alignment: .leading, spacing: 22) {
            if !combined.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(LibraryKind.allCases) { value in
                            let count = combined.filter { value == .all || $0.media?.type == value.rawValue }.count
                            HarborPill(title: text(value.title) + "  \(count)", selected: kind == value) { kind = value }
                                .accessibilityIdentifier("trakt-library-kind-" + value.rawValue)
                        }
                    }
                }.scrollIndicators(.hidden)
                HarborSearchField(prompt: text("Search title…"), text: $query).accessibilityIdentifier("trakt-library-search")
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(LibrarySort.allCases) { value in
                            HarborPill(title: text(value.title), selected: app.library.presentation.display.sort == value) { app.library.changeDisplay { $0.sort = value } }
                                .accessibilityIdentifier("trakt-library-sort-" + value.rawValue)
                        }
                    }
                }.scrollIndicators(.hidden)
            }
            section(model.watchlist, title: "Trakt watchlist", empty: "Nothing saved on Trakt yet.", history: false)
            section(model.history, title: "Trakt history", empty: "No history yet.", history: true)
            if let error = model.error {
                VStack(alignment: .leading, spacing: 10) {
                    Text(text(error)).font(.callout).foregroundStyle(.orange)
                    Button(text("Retry")) { Task { await model.refresh(force: true) } }.frame(minHeight: 44)
                }.accessibilityIdentifier("trakt-library-error")
            }
        }.accessibilityIdentifier("trakt-library-content").task { await model.refresh() }.onDisappear { model.cancel() }
    }
    private func section(_ records: [LibraryRecord], title: String, empty: String, history: Bool) -> some View {
        var display = app.library.presentation.display; display.kind = kind; display.filter = history ? .watched : .watchlist
        let visible = LibraryListing.select(records, display: display, query: query), groups = LibraryListing.groups(visible, display: display)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(text(title)).font(HarborTheme.font(18, weight: .semibold)).accessibilityAddTraits(.isHeader)
                Text(text("{shown} of {total}", variables: ["shown": String(visible.count), "total": String(records.count)])).font(.caption).foregroundStyle(.secondary)
                if model.loading && !records.isEmpty { ProgressView().controlSize(.small) }
            }
            if model.loading && records.isEmpty { ProgressView(text("Loading…")).frame(maxWidth: .infinity) }
            else if visible.isEmpty {
                Text(text(records.isEmpty ? empty : "No matches for these filters.")).font(.callout).foregroundStyle(.secondary).padding(.vertical, 12)
            } else {
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    VStack(alignment: .leading, spacing: 14) {
                        if !group.title.isEmpty { Text(text(group.title).uppercased() + "  \(group.items.count)").font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(.secondary) }
                        PosterGrid(spacing: 22) {
                            ForEach(group.items) { record in
                                if let media = record.media {
                                    TraktLibraryCard(app: app, model: model, media: media, removable: !history, metadata: metadata)
                                }
                            }
                        }
                    }
                }
            }
        }.accessibilityIdentifier(history ? "trakt-library-history" : "trakt-library-watchlist").id(history ? "trakt-history" : "trakt-watchlist")
    }
}

private struct TraktLibraryCard: View {
    let app: AppModel
    let model: TraktLibraryModel
    let media: Media
    let removable: Bool
    let metadata: (@MainActor (Media) async throws -> Media)?
    @State private var hydrated: Media?
    var body: some View {
        NavigationLink { DetailView(media: hydrated ?? media, app: app, metadataLoaded: hydrated != nil) } label: { Poster(media: hydrated ?? media, width: nil) }
            .buttonStyle(.plain).accessibilityLabel(media.name).accessibilityIdentifier("trakt-library-media")
            .contextMenu {
                if removable, let target = TraktLibraryTarget(media) {
                    Button(DesktopInterfaceText.value("Remove from watchlist"), role: .destructive) { Task {
                        await model.setWatchlisted(false, target: target, title: media.name, year: media.releaseInfo.flatMap { Int($0) })
                    } }.disabled(model.store.updating)
                }
            }.task(id: app.accountOperationScope + "|" + media.identity) {
                let scope = app.accountOperationScope
                let value: Media?
                if let metadata { value = try? await metadata(media) } else { value = try? await app.continuationMetadata(media) }
                guard let value, !Task.isCancelled, scope == app.accountOperationScope else { return }
                hydrated = value
            }
    }
}

struct TraktWatchlistTransferView: View {
    let model: TraktLibraryModel
    let library: LibraryModel
    private enum Phase { case idle, loading, export(TraktWatchlistExportPlan), importItems([TraktLibraryItem]), running(Bool), result(String) }
    @State private var phase = Phase.idle
    private func text(_ key: String, variables: [String: String] = [:]) -> String { DesktopInterfaceText.value(key, variables: variables) }
    private var busy: Bool {
        switch phase { case .idle, .result: model.loading || model.transferring || model.store.updating; default: true }
    }
    var body: some View {
        HarborSettingsSection("Move your watchlist", note: "Copy your Harbor watchlist over to Trakt, or pull your Trakt watchlist into Harbor.") {
            VStack(alignment: .leading, spacing: 12) {
                Text(text("Send every title in your Harbor watchlist up to Trakt. Safe to run again, Trakt skips anything it already has.")).font(.callout).foregroundStyle(.secondary)
                Button(text("Export to Trakt")) {
                    let plan = TraktLibraryModel.exportPlan(library.items)
                    if plan.exportable > 0 { phase = .export(plan) }
                    else { phase = .result(text(plan.skippedAnime > 0 ? "Nothing to send. All {n} watchlist items are anime, which Trakt can't track." : "Your watchlist is empty, nothing to send.", variables: ["n": String(plan.skippedAnime)])) }
                }.buttonStyle(HarborAccountButtonStyle()).disabled(busy || !library.canSaveBookmarks).accessibilityIdentifier("trakt-export-watchlist")
                Text(text("Pull every title on your Trakt watchlist into Harbor. Anything already saved is left alone.")).font(.callout).foregroundStyle(.secondary)
                Button(text("Import from Trakt")) { phase = .loading; Task {
                    if let items = await model.fetchImport() { phase = items.isEmpty ? .result(text("Your Trakt watchlist is empty, nothing to import.")) : .importItems(items) }
                    else { phase = .result(text(model.error ?? "Couldn't reach Trakt. Check your connection and try again.")) }
                } }.buttonStyle(HarborAccountButtonStyle()).disabled(busy || !library.canSaveBookmarks).accessibilityIdentifier("trakt-import-watchlist")
                feedback
            }
        }.task { model.loadAccount() }.onDisappear { model.cancel() }
            .onChange(of: model.account.session?.trackingID) { _, _ in phase = .idle; model.cancel(); model.loadAccount() }
    }
    @ViewBuilder private var feedback: some View {
        switch phase {
        case .idle: EmptyView()
        case .loading: ProgressView(text("Loading…")).frame(maxWidth: .infinity)
        case .export(let plan):
            VStack(alignment: .leading, spacing: 12) {
                Text(text("Add {n} titles from your Harbor watchlist to Trakt? Trakt skips any it already has.", variables: ["n": String(plan.exportable)]))
                if plan.skippedAnime > 0 { Text(text("{n} anime titles will be left out (Trakt has no IDs for them).", variables: ["n": String(plan.skippedAnime)])).font(.caption).foregroundStyle(.secondary) }
                confirmation { phase = .running(true); Task {
                    if let result = await model.export(plan) {
                        var parts = [text("Sent {n} to Trakt", variables: ["n": String(result.synced)])]
                        if result.skippedAnime > 0 { parts.append(text("skipped {n} anime", variables: ["n": String(result.skippedAnime)])) }
                        if result.unmatched > 0 { parts.append(text("{n} not matched", variables: ["n": String(result.unmatched)])) }
                        phase = .result(parts.joined(separator: " · "))
                    } else { phase = .result(text(model.error ?? "Couldn't reach Trakt. Check your connection and try again.")) }
                } }
            }.accessibilityIdentifier("trakt-export-confirmation")
        case .importItems(let items):
            VStack(alignment: .leading, spacing: 12) {
                Text(text("Add {n} titles from your Trakt watchlist to Harbor?", variables: ["n": String(items.count)]))
                confirmation {
                    let owner = library.owner, personalOwner = library.personalOwner
                    phase = .running(false); Task {
                        let count = await model.importItems(items) { media in await library.saveBookmark(media, owner: owner, personalOwner: personalOwner) }
                        if let count { phase = .result(text("Added {n} to your Harbor watchlist", variables: ["n": String(count)])) }
                        else { phase = .idle }
                    }
                }
            }.accessibilityIdentifier("trakt-import-confirmation")
        case .running(let exporting):
            HStack(spacing: 10) { ProgressView(); Text(text(exporting ? "Sending to Trakt…" : "Importing {done} / {total}", variables: ["done": String(model.completed), "total": String(model.total)])) }
                .accessibilityIdentifier("trakt-transfer-progress")
        case .result(let message):
            VStack(alignment: .leading, spacing: 10) {
                Text(message).font(.callout).accessibilityIdentifier("trakt-transfer-result")
                Button(text("Done")) { phase = .idle }.frame(minHeight: 44)
            }
        }
    }
    private func confirmation(_ proceed: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Button(text("Continue"), action: proceed).buttonStyle(HarborAccountButtonStyle(primary: true)).accessibilityIdentifier("trakt-transfer-confirm")
            Button(text("Cancel")) { phase = .idle }.frame(minHeight: 44).accessibilityIdentifier("trakt-transfer-cancel")
        }
    }
}
