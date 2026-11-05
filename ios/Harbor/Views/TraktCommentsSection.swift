import SwiftUI

/// Desktop's "Trakt Comments" section of a detail page (`views/detail/trakt-comments.tsx`), for reading:
/// sorting, spoilers, replies and paging. Posting, likes and ratings need the Trakt account and are not ported.
struct TraktCommentsSection: View {
    let media: Media
    var service = TraktCommentsService()
    @State private var comments: [TraktComment] = []
    @State private var page = 1
    @State private var hasMore = false
    @State private var loading = true
    @State private var loadingMore = false
    @State private var sort = TraktCommentSort.likes
    @State private var collapsed = false
    @State private var revealed = false
    @Environment(\.openURL) private var openURL
    private func text(_ key: String, _ count: Int? = nil) -> String {
        DesktopInterfaceText.value(key, variables: count.map { ["n": String($0)] } ?? [:])
    }
    private var resolution: TraktCommentTarget.Resolution { TraktCommentTarget.resolve(media) }
    private var blurred: Bool { InterfacePreferences.shared.blurComments && !revealed }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if !collapsed { content }
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("trakt-comments")
        .task(id: media.identity + "|" + sort.rawValue) { await load() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(text("Trakt Comments")).font(HarborTheme.font(20, weight: .bold)).accessibilityAddTraits(.isHeader)
            Button { collapsed.toggle() } label: {
                Image(systemName: "chevron.down").rotationEffect(.degrees(collapsed ? -90 : 0)).frame(width: 36, height: 36).contentShape(Rectangle())
            }.accessibilityLabel(text(collapsed ? "Show comments" : "Hide comments")).accessibilityIdentifier("trakt-comments-collapse")
            Spacer(minLength: 8)
            if case .target(let target) = resolution, !collapsed {
                Menu {
                    ForEach(TraktCommentSort.allCases, id: \.self) { option in
                        Button { sort = option } label: {
                            if option == sort { Label(text(option.label), systemImage: "checkmark") } else { Text(text(option.label)) }
                        }
                    }
                } label: {
                    Label(text(sort.label), systemImage: "chevron.down").labelStyle(.titleAndIcon).font(.footnote.weight(.medium))
                        .padding(.horizontal, 12).frame(minHeight: 36).background(.white.opacity(0.06), in: .capsule)
                }.accessibilityIdentifier("trakt-comments-sort")
                if let url = target.pageURL {
                    Button { openURL(url) } label: {
                        Text(text("Open on Trakt")).font(.footnote.weight(.medium)).padding(.horizontal, 12).frame(minHeight: 36)
                            .background(.white.opacity(0.06), in: .capsule)
                    }.accessibilityIdentifier("trakt-comments-open")
                }
            }
        }.buttonStyle(.plain)
    }

    @ViewBuilder private var content: some View {
        switch resolution {
        case .anime:
            notice(text("Trakt comments are not available for anime titles."))
        case .unidentified:
            notice(text("Could not identify this title on Trakt."))
        case .target:
            ZStack {
                list.blur(radius: blurred ? 8 : 0).allowsHitTesting(!blurred).accessibilityHidden(blurred)
                if blurred {
                    VStack(spacing: 8) {
                        Button { revealed = true } label: {
                            Text(text("Reveal comments")).font(.footnote.weight(.semibold)).padding(.horizontal, 18).frame(minHeight: 44)
                                .foregroundStyle(HarborTheme.background).background(HarborTheme.ink, in: .capsule)
                        }.accessibilityIdentifier("trakt-comments-reveal")
                        Text(text("Comments are hidden")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func notice(_ message: String) -> some View {
        Text(message).font(.footnote).foregroundStyle(.secondary).padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(HarborTheme.surface, in: .rect(cornerRadius: 12))
    }

    @ViewBuilder private var list: some View {
        if loading {
            ProgressView().frame(maxWidth: .infinity, minHeight: 80)
        } else if comments.isEmpty {
            Text(text("No comments yet")).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        } else {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(comments) { comment in TraktCommentCard(comment: comment, service: service) }
                if hasMore {
                    Button { Task { await loadMore() } } label: {
                        HStack(spacing: 8) {
                            if loadingMore { ProgressView().controlSize(.small) }
                            Text(text(loadingMore ? "Loading more" : "Load more comments")).font(.footnote.weight(.semibold))
                        }.frame(maxWidth: .infinity, minHeight: 44).background(.white.opacity(0.06), in: .rect(cornerRadius: 12))
                    }.buttonStyle(.plain).disabled(loadingMore).accessibilityIdentifier("trakt-comments-more")
                }
            }
        }
    }

    private func load() async {
        guard case .target(let target) = resolution else { loading = false; return }
        loading = true; page = 1
        let found = await service.comments(target, sort: sort, page: 1)
        guard !Task.isCancelled else { return }
        comments = found; hasMore = found.count >= TraktCommentsService.pageSize; loading = false
    }

    private func loadMore() async {
        guard case .target(let target) = resolution, !loadingMore, hasMore else { return }
        loadingMore = true
        let next = page + 1
        let found = await service.comments(target, sort: sort, page: next)
        let known = Set(comments.map(\.id))
        comments += found.filter { !known.contains($0.id) }
        page = next; hasMore = found.count >= TraktCommentsService.pageSize; loadingMore = false
    }
}

private struct TraktCommentCard: View {
    let comment: TraktComment
    let service: TraktCommentsService
    @State private var revealed = false
    @State private var replies: [TraktComment]?
    @State private var loadingReplies = false
    private func text(_ key: String, _ count: Int? = nil) -> String {
        DesktopInterfaceText.value(key, variables: count.map { ["n": String($0)] } ?? [:])
    }
    private var age: String? {
        guard let date = ISO8601DateParser.shared.date(comment.createdAt) else { return nil }
        return TraktComment.ago(from: date) { key, count in text(key, count) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar(comment, size: 36)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(comment.displayName).font(.footnote.weight(.semibold))
                    if let age { Text(age).font(.caption2).foregroundStyle(.secondary) }
                    Spacer(minLength: 4)
                    if let rating = comment.userRating, rating > 0 {
                        Label((Double(rating) / 2).formatted(.number.precision(.fractionLength(0...1))), systemImage: "star.fill")
                            .font(.caption.weight(.medium)).foregroundStyle(.yellow)
                    }
                }
                if comment.spoiler && !revealed {
                    Button { revealed = true } label: {
                        Label(text("Spoiler — Click to reveal"), systemImage: "eye").font(.caption.weight(.medium)).foregroundStyle(.yellow)
                            .padding(.horizontal, 12).frame(minHeight: 36).background(.yellow.opacity(0.12), in: .rect(cornerRadius: 8))
                    }.buttonStyle(.plain)
                } else {
                    Text(comment.comment).font(.footnote).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                HStack(spacing: 14) {
                    Label("\(comment.likes)", systemImage: "heart").font(.caption).foregroundStyle(.secondary)
                    if comment.replies > 0 {
                        Button { Task { await toggleReplies() } } label: {
                            HStack(spacing: 4) {
                                if loadingReplies { ProgressView().controlSize(.mini) } else { Image(systemName: "bubble.left") }
                                Text("\(comment.replies)")
                            }.font(.caption).foregroundStyle(.secondary).frame(minHeight: 36)
                        }.buttonStyle(.plain).accessibilityIdentifier("trakt-comment-replies-\(comment.id)")
                    }
                }
                if let replies {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(replies) { reply in
                            HStack(alignment: .top, spacing: 8) {
                                avatar(reply, size: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(reply.displayName).font(.caption.weight(.semibold))
                                    ReplyBody(reply: reply)
                                }
                            }
                        }
                    }.padding(.leading, 12).overlay(alignment: .leading) { Rectangle().fill(.white.opacity(0.12)).frame(width: 2) }
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(HarborTheme.surface, in: .rect(cornerRadius: 14))
    }

    private func avatar(_ comment: TraktComment, size: CGFloat) -> some View {
        ZStack {
            Circle().fill(.secondary.opacity(0.2))
            Text(String(comment.displayName.prefix(1)).uppercased()).font(.system(size: size * 0.4, weight: .semibold)).foregroundStyle(.secondary)
            if let url = comment.avatarURL { Artwork(url: url, maxPixels: 120, showsPlaceholder: false).clipShape(.circle) }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }

    private func toggleReplies() async {
        if replies != nil { replies = nil; return }
        loadingReplies = true
        replies = await service.replies(to: comment.id)
        loadingReplies = false
    }
}

/// A reply hides a spoiler behind a small label, as Desktop's `SpoilerLabel` does.
private struct ReplyBody: View {
    let reply: TraktComment
    @State private var shown = false
    var body: some View {
        if reply.spoiler && !shown {
            Button { shown = true } label: {
                Text(DesktopInterfaceText.value("Spoiler — Click")).font(.caption2.weight(.medium)).foregroundStyle(.yellow)
                    .padding(.horizontal, 8).frame(minHeight: 28).background(.yellow.opacity(0.12), in: .rect(cornerRadius: 6))
            }.buttonStyle(.plain)
        } else {
            Text(reply.comment).font(.caption).fixedSize(horizontal: false, vertical: true)
        }
    }
}
