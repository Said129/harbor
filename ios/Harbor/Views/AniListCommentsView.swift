import SwiftUI

/// Desktop's "AniList Comments" section (`views/detail/anilist-comments.tsx`), read-only: the forum threads of an
/// anime, their comments and the spoiler blur. Posting threads and comments, likes and deletes write to AniList
/// and are not ported. The caller shows this only for anime, with the AniList Comments setting on.
struct AniListCommentsSection: View {
    let media: Media
    let app: AppModel
    @State private var account: AniListAccount
    @State private var resolved = false
    @State private var mediaID: Int?
    @State private var threads: [AniListThread] = []
    @State private var page = 1
    @State private var hasMore = false
    @State private var loading = true
    @State private var loadingMore = false
    @State private var failed = false
    @State private var open: AniListThread?
    @State private var comments: [AniListThreadComment] = []
    @State private var loadingComments = false
    @State private var revealed = false
    private let preferences = AniListPreferences.shared
    @Environment(\.openURL) private var openURL

    @MainActor init(media: Media, app: AppModel) {
        self.media = media
        self.app = app
        _account = State(initialValue: AniListAccount.forOwner(app.personalOwner))
    }

    private func text(_ key: String, _ count: Int? = nil) -> String {
        DesktopInterfaceText.value(key, variables: count.map { ["n": String($0)] } ?? [:])
    }
    private var blurred: Bool { preferences.anilistBlurComments && !revealed }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            content
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("anilist-comments")
        .task(id: media.identity) { await resolve() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let open {
                Button { self.open = nil } label: {
                    Label(text("Back to threads"), systemImage: "chevron.left").font(.footnote.weight(.medium))
                        .padding(.horizontal, 12).frame(minHeight: 36).background(.white.opacity(0.06), in: .capsule)
                }.accessibilityIdentifier("anilist-comments-back")
                Spacer(minLength: 8)
                Text(open.title).font(.footnote.weight(.semibold)).lineLimit(1)
            } else {
                Text(text("AniList Comments")).font(HarborTheme.font(20, weight: .bold)).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
            }
        }.buttonStyle(.plain)
    }

    @ViewBuilder private var content: some View {
        if !resolved {
            ProgressView().frame(maxWidth: .infinity, minHeight: 80)
        } else if account.session == nil {
            notice(text("Connect your AniList account to see forum threads and comments."))
        } else if mediaID == nil {
            notice(text("Could not find this title on AniList."))
        } else {
            ZStack {
                listContent(for: open).blur(radius: blurred ? 8 : 0).allowsHitTesting(!blurred).accessibilityHidden(blurred)
                if blurred { revealOverlay }
            }
        }
    }

    private var revealOverlay: some View {
        VStack(spacing: 8) {
            Button { revealed = true } label: {
                Text(text("Reveal comments")).font(.footnote.weight(.semibold)).padding(.horizontal, 18).frame(minHeight: 44)
                    .foregroundStyle(HarborTheme.background).background(HarborTheme.ink, in: .capsule)
            }.buttonStyle(.plain).accessibilityIdentifier("anilist-comments-reveal")
            Text(text("Comments are hidden")).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func listContent(for thread: AniListThread?) -> some View {
        if let thread {
            threadDetail(thread)
        } else if loading {
            ProgressView().frame(maxWidth: .infinity, minHeight: 80)
        } else if failed || threads.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(text("No threads for this title yet.")).font(.footnote.weight(.semibold))
                Text(text("Be the first to start a discussion.")).font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(threads) { thread in threadRow(thread) }
                if hasMore { moreButton }
            }
        }
    }

    private func threadRow(_ thread: AniListThread) -> some View {
        Button { open = thread; Task { await loadComments(thread) } } label: {
            HStack(alignment: .center, spacing: 12) {
                AniListAvatar(url: thread.author.avatar, name: thread.author.name ?? text("Unknown"), size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(thread.title).font(.footnote.weight(.semibold)).lineLimit(2)
                        if thread.isLocked { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary).accessibilityLabel(text("This thread is locked.")) }
                    }
                    HStack(spacing: 8) {
                        Text(threadMeta(thread))
                        Label("\(thread.replyCount)", systemImage: "bubble.left")
                        Label("\(thread.viewCount)", systemImage: "eye")
                    }.font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondary)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(HarborTheme.surface, in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain).accessibilityIdentifier("anilist-thread-\(thread.id)")
    }

    private func threadMeta(_ thread: AniListThread) -> String {
        let name = thread.author.name ?? text("Unknown")
        let age = AniListThreads.ago(unixSeconds: thread.createdAt) { key, count in text(key, count) }
        return name + "  " + age
    }

    private func threadDetail(_ thread: AniListThread) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if !thread.body.isEmpty { Text(thread.body).font(.footnote).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) }
            if thread.isLocked { Text(text("This thread is locked.")).font(.caption).foregroundStyle(.secondary) }
            if loadingComments {
                ProgressView().frame(maxWidth: .infinity, minHeight: 60)
            } else if comments.isEmpty {
                Text(text("No comments yet")).font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(comments) { comment in commentRow(comment) }
            }
            if let url = thread.siteURL.flatMap({ URL(string: $0) }) {
                Button { openURL(url) } label: {
                    Text(text("Open on AniList")).font(.footnote.weight(.medium)).padding(.horizontal, 12).frame(minHeight: 36)
                        .background(.white.opacity(0.06), in: .capsule)
                }.buttonStyle(.plain).accessibilityIdentifier("anilist-thread-open")
            }
        }
    }

    private func commentRow(_ comment: AniListThreadComment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            AniListAvatar(url: comment.author.avatar, name: comment.author.name ?? text("Unknown"), size: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment.author.name ?? text("Unknown")).font(.caption.weight(.semibold))
                    Text(AniListThreads.ago(unixSeconds: comment.createdAt) { key, count in text(key, count) }).font(.caption2).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Label("\(comment.likes)", systemImage: comment.isLiked ? "heart.fill" : "heart").font(.caption).foregroundStyle(.secondary)
                }
                Text(comment.text).font(.footnote).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(HarborTheme.surface, in: .rect(cornerRadius: 12))
    }

    private var moreButton: some View {
        Button { Task { await loadMore() } } label: {
            HStack(spacing: 8) {
                if loadingMore { ProgressView().controlSize(.small) }
                Text(text(loadingMore ? "Loading more" : "Load more threads")).font(.footnote.weight(.semibold))
            }.frame(maxWidth: .infinity, minHeight: 44).background(.white.opacity(0.06), in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain).disabled(loadingMore).accessibilityIdentifier("anilist-threads-more")
    }

    private func notice(_ message: String) -> some View {
        Text(message).font(.footnote).foregroundStyle(.secondary).padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(HarborTheme.surface, in: .rect(cornerRadius: 12))
    }

    // MARK: Loading

    private func resolve() async {
        if !account.ready { try? account.load() }
        threads = []; page = 1; hasMore = false; open = nil; comments = []; resolved = false; mediaID = nil; revealed = false
        guard let session = account.session, session.isActive() else { loading = false; resolved = true; return }
        loading = true
        let found = await AniListThreadsService.anilistID(for: media.id, token: session.accessToken)
        guard !Task.isCancelled else { return }
        mediaID = found; resolved = true
        if found != nil { await loadPage(1) }
        loading = false
    }

    private func loadPage(_ next: Int) async {
        guard let mediaID, let token = account.session?.accessToken else { return }
        let service = AniListThreadsService(client: AniListClient(transport: AniListHTTPTransport()), token: token)
        do {
            let result = try await service.threads(mediaID: mediaID, page: next)
            guard !Task.isCancelled else { return }
            if next == 1 {
                threads = result.threads
            } else {
                let known = Set(threads.map(\.id))
                threads += result.threads.filter { !known.contains($0.id) }
            }
            page = next; hasMore = result.hasNextPage; failed = false
        } catch {
            if next == 1 { failed = true }
        }
    }

    private func loadMore() async {
        guard !loadingMore, hasMore else { return }
        loadingMore = true
        await loadPage(page + 1)
        loadingMore = false
    }

    private func loadComments(_ thread: AniListThread) async {
        guard let token = account.session?.accessToken else { return }
        loadingComments = true; comments = []
        let service = AniListThreadsService(client: AniListClient(transport: AniListHTTPTransport()), token: token)
        let found = (try? await service.comments(threadID: thread.id)) ?? []
        guard open?.id == thread.id else { return }
        comments = found; loadingComments = false
    }
}

/// A round avatar with the first letter as the fallback, as Desktop's `Avatar` in the comments view.
private struct AniListAvatar: View {
    let url: String?
    let name: String
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(.secondary.opacity(0.2))
            Text(String(name.prefix(1)).uppercased()).font(.system(size: size * 0.4, weight: .semibold)).foregroundStyle(.secondary)
            if let url { Artwork(url: url, maxPixels: 120, showsPlaceholder: false).clipShape(.circle) }
        }
        .frame(width: size, height: size).accessibilityHidden(true)
    }
}
