import SwiftUI

struct SimklLibraryContent: View {
    let app: AppModel
    let model: SimklLibraryModel
    @State private var kind: SimklMediaKind
    @State private var status: SimklListStatus
    @State private var query = ""
    init(app: AppModel, model: SimklLibraryModel, kind: SimklMediaKind = .movie, status: SimklListStatus = .plantowatch) {
        self.app = app; self.model = model; _kind = State(initialValue: kind)
        _status = State(initialValue: SimklListStatus.options(for: kind).contains(status) ? status : .plantowatch)
    }
    private var sort: LibrarySort { app.library.presentation.display.sort }
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }
    var body: some View {
        let prepared = model.collection, counts = prepared.counts(kind: kind)
        let rows = prepared.rows(kind: kind, status: status, query: query), groups = SimklCollection.groups(rows, sort: sort)
        VStack(alignment: .leading, spacing: 18) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(SimklMediaKind.allCases) { value in
                        HarborPill(title: text(value.label), selected: kind == value) { kind = value }
                            .accessibilityIdentifier("simkl-kind-\(value.rawValue)")
                    }
                }
            }.scrollIndicators(.hidden)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(SimklListStatus.options(for: kind)) { value in
                        let count = counts[value, default: 0]
                        HarborPill(title: "\(text(value.label))  \(count)", selected: status == value) { status = value }
                            .accessibilityIdentifier("simkl-status-\(value.rawValue)")
                    }
                }
            }.scrollIndicators(.hidden)
            HarborSearchField(prompt: text("Search title…"), text: $query).accessibilityIdentifier("simkl-library-search")
            HStack(spacing: 6) {
                ForEach(LibrarySort.allCases) { value in
                    HarborPill(title: text(value == .recent ? "Recent" : value == .title ? "A-Z" : "Year"), selected: sort == value) { app.library.changeDisplay { $0.sort = value } }
                        .accessibilityIdentifier("simkl-sort-\(value.rawValue)")
                }
            }.disabled(!app.library.canChangePresentation)
            if model.loading { ProgressView(text("Loading…")).frame(maxWidth: .infinity).accessibilityIdentifier("simkl-library-loading") }
            if let error = model.error {
                VStack(alignment: .leading, spacing: 10) {
                    Text(text(error)).foregroundStyle(.orange).font(.callout)
                    Button(text("Retry")) { Task { await model.refresh(force: true) } }.frame(minHeight: 44)
                }.accessibilityIdentifier("simkl-library-error")
            }
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 14) {
                    Text("\(text(group.label).uppercased())  \(group.rows.count)").font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(.secondary)
                    PosterGrid(spacing: 22) {
                        ForEach(group.rows) { row in
                            NavigationLink { DetailView(media: row.media, app: app) } label: { Poster(media: row.media, width: nil) }
                                .buttonStyle(.plain).accessibilityLabel(row.media.name).accessibilityIdentifier("simkl-library-media")
                                .contextMenu {
                                    ForEach(row.items) { item in
                                        Menu(item.title) {
                                            ForEach(SimklListStatus.options(for: item.kind)) { value in
                                                Button(text(value.label)) { Task { await model.setStatus(value, target: item.target, media: item.media) } }
                                            }
                                            Button(text("Remove from list"), role: .destructive) { Task { await model.setStatus(nil, target: item.target, media: item.media) } }
                                        }
                                    }
                                }.disabled(model.store.updating)
                        }
                    }
                }
            }
            if rows.isEmpty && !model.loading {
                Text(text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No items found in this section." : "No matches for these filters."))
                    .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 80).accessibilityIdentifier("simkl-library-empty")
            }
        }.accessibilityIdentifier("simkl-library-content")
            .onChange(of: kind) { _, value in if !SimklListStatus.options(for: value).contains(status) { status = SimklListStatus.options(for: value)[0] } }
            .task { await model.refresh() }
            .task(id: "\(kind.rawValue):\(model.store.revision)") { if kind == .anime { await model.loadRelations() } }
            .onDisappear { model.cancel() }
    }
}

struct SimklDetailControls: View {
    let media: Media
    @State private var model: SimklLibraryModel
    @State private var target: SimklTarget?
    @State private var presenting = false
    @AppStorage("simklEnableUserRatings") private var ratings = true
    @MainActor init(media: Media, app: AppModel) { self.media = media; _model = State(initialValue: SimklLibraryModel(app: app)) }
    private var item: SimklListItem? { target.flatMap { model.store.snapshot.item(for: $0) } }
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }
    var body: some View {
        Group {
            if model.account.session != nil, let target {
                VStack(alignment: .leading, spacing: 10) {
                    Button { presenting = true } label: {
                        HStack(spacing: 10) {
                            Image("tracker-simkl").resizable().scaledToFit().frame(width: 20, height: 20)
                            Text(text(item?.status.label ?? "Add to Simkl")).font(HarborTheme.font(14, weight: .medium))
                            if model.store.updating { ProgressView().controlSize(.small) } else { Image(systemName: item == nil ? "plus" : "chevron.down").font(.caption) }
                        }.padding(.horizontal, 18).frame(minHeight: 48).background(HarborTheme.surface, in: .capsule)
                            .overlay { Capsule().stroke(item == nil ? HarborTheme.ink.opacity(0.2) : HarborTheme.ink.opacity(0.65)) }
                    }.buttonStyle(.plain).disabled(model.store.updating || model.loading).accessibilityIdentifier("simkl-detail-status")
                    if let error = model.error { Text(text(error)).font(.caption).foregroundStyle(.orange).accessibilityIdentifier("simkl-detail-error") }
                }.sheet(isPresented: $presenting) {
                    SimklTitleActions(media: media, target: target, model: model, ratings: ratings).presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
                }
            }
        }.task(id: media.identity + "|" + (model.account.session.map { EBookShelf.hash($0.accessToken) } ?? "disconnected")) {
            model.loadAccount(); guard let token = model.account.session?.accessToken else { target = nil; return }
            let resolved = try? await SimklTarget.resolve(media)
            guard !Task.isCancelled, model.account.session?.accessToken == token else { return }
            target = resolved
            if target != nil { await model.refresh() }
        }.onDisappear { model.cancel() }
    }
}

struct SimklTitleActions: View {
    let media: Media
    let target: SimklTarget
    let model: SimklLibraryModel
    let ratings: Bool
    @Environment(\.dismiss) private var dismiss
    private var item: SimklListItem? { model.store.snapshot.item(for: target) }
    private var rating: Int? { model.store.snapshot.rating(for: target) }
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(SimklListStatus.options(for: target.kind)) { status in
                        Button {
                            Task { await model.setStatus(status, target: target, media: media); if model.error == nil { dismiss() } }
                        } label: {
                            HStack { Text(text(status.label)); Spacer(); if item?.status == status { Image(systemName: "checkmark") } }.frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("simkl-title-status-\(status.rawValue)")
                    }
                    if ratings {
                        Divider()
                        Text(text("Your rating")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        SimklStarPicker(rating: rating, busy: model.store.updating) { value in
                            Task { await model.setRating(value == rating ? nil : value, target: target) }
                        }
                    }
                    if item != nil {
                        Divider()
                        Button(role: .destructive) {
                            Task { await model.setStatus(nil, target: target, media: media); if model.error == nil { dismiss() } }
                        } label: { Label(text("Remove from list"), systemImage: "trash").frame(minHeight: 44) }.accessibilityIdentifier("simkl-title-remove")
                    }
                    if let error = model.error { Text(text(error)).foregroundStyle(.orange).font(.caption).accessibilityIdentifier("simkl-title-error") }
                    if model.store.updating { ProgressView().frame(maxWidth: .infinity) }
                }.padding(22).frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
                    .disabled(model.store.updating)
            }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink)
                .navigationTitle(media.name).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(text("Done")) { dismiss() } } }
        }
    }
}

struct SimklStarPicker: View {
    let rating: Int?
    let busy: Bool
    let select: (Int) -> Void
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: (rating ?? 0) >= star * 2 ? "star.fill" : rating == star * 2 - 1 ? "star.leadinghalf.filled" : "star")
                        .font(.system(size: 26)).foregroundStyle(.yellow).frame(maxWidth: .infinity).frame(height: 48)
                        .overlay {
                            HStack(spacing: 0) {
                                ratingButton(star * 2 - 1)
                                ratingButton(star * 2)
                            }
                        }.accessibilityHidden(true)
                }
            }.accessibilityElement(children: .ignore).accessibilityLabel(text("Your rating"))
                .accessibilityValue(rating.map { "\($0)/10" } ?? text("Rate on SIMKL"))
                .accessibilityAdjustableAction { direction in
                    if direction == .increment { select(min(10, (rating ?? 0) + 1)) }
                    else if direction == .decrement { select(max(1, (rating ?? 2) - 1)) }
                }.disabled(busy).accessibilityIdentifier("simkl-star-picker")
            HStack {
                Text(rating.map { "\($0)/10" } ?? text("Rate on SIMKL")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Menu(text("Your rating")) {
                    ForEach(1...10, id: \.self) { number in Button("\(number)/10") { select(number) } }
                }.frame(minHeight: 44).disabled(busy).accessibilityIdentifier("simkl-rating-menu")
            }
        }
    }
    private func ratingButton(_ value: Int) -> some View {
        Button { select(value) } label: { Color.clear.contentShape(Rectangle()) }.buttonStyle(.plain).frame(maxWidth: .infinity, minHeight: 48)
    }
}
