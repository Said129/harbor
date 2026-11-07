import Foundation

/// Desktop's AniList forum threads and thread comments (`lib/anilist/threads.ts`) and anime relations
/// (`lib/anilist/relations.ts`, `animeRelations`). Pure value logic: the parsers take the GraphQL `data` object,
/// so the tests need no network. Writing (new threads, comments, likes, deletes) is not ported.
struct AniListThreadAuthor: Equatable, Sendable {
    let id: Int
    /// Nil when AniList sends no user, which Desktop shows as "Unknown".
    let name: String?
    let avatar: String?
}

struct AniListThread: Identifiable, Equatable, Sendable {
    let id: Int
    let title: String
    /// The body as plain text, from the `asHtml` body that Desktop renders.
    let body: String
    let replyCount: Int
    let viewCount: Int
    let isLocked: Bool
    let isSticky: Bool
    /// Unix seconds, as AniList sends them.
    let createdAt: Int
    let siteURL: String?
    let author: AniListThreadAuthor
}

/// Desktop's `AnilistThreadComment`. Comments are a flat list under their thread; there are no nested replies.
struct AniListThreadComment: Identifiable, Equatable, Sendable {
    let id: Int
    let text: String
    let likes: Int
    let isLiked: Bool
    let createdAt: Int
    let siteURL: String?
    let author: AniListThreadAuthor
}

/// Desktop's `AnimeRelation`: a prequel or a sequel of a TV or OVA title (movies are left out).
struct AniListRelation: Identifiable, Equatable, Sendable {
    enum Kind: String, Equatable, Sendable { case prequel, sequel }
    let id: Int
    let name: String
    let year: Int?
    let format: String?
    let poster: String?
    let kind: Kind
    let upcoming: Bool
}

/// One edge of `Media.relations`, reduced to what `animeRelations` reads.
struct AniListRelationEdge: Equatable, Sendable {
    let relationType: String?
    let node: AniListRelationNode?
}

struct AniListRelationNode: Equatable, Sendable {
    let id: Int
    let format: String?
    let status: String?
    let english: String?
    let romaji: String?
    let userPreferred: String?
    let seasonYear: Int?
    let startYear: Int?
    let poster: String?
}

enum AniListThreads {
    /// Desktop's `THREADS_QUERY`, with the same selection set on one line.
    static let threadsQuery = "query ($mediaId: Int, $page: Int, $perPage: Int) { Page(page: $page, perPage: $perPage) { threads(mediaCategoryId: $mediaId, sort: [ID_DESC]) { id title bodyHtml: body(asHtml: true) replyCount viewCount isLocked isSticky createdAt updatedAt siteUrl user { id name avatar { medium large } } } pageInfo { currentPage lastPage hasNextPage } } }"

    /// Desktop's `COMMENTS_QUERY`.
    static let commentsQuery = "query ($threadId: Int) { Page { threadComments(threadId: $threadId, sort: [ID]) { id commentHtml: comment(asHtml: true) likeCount isLiked createdAt siteUrl user { id name avatar { medium large } } } } }"

    /// Desktop's `RELATIONS_QUERY` in `lib/anilist/relations.ts`.
    static let relationsQuery = "query ($id: Int) { Media(id: $id, type: ANIME) { relations { edges { relationType(version: 2) node { id format episodes status averageScore seasonYear title { english romaji userPreferred } coverImage { large } bannerImage description(asHtml: false) startDate { year month day } } } } } }"

    /// Desktop's `animeRelations` walks at most this many titles before it stops adding a level.
    static let maxRelations = 20

    // MARK: Threads and comments

    static func threadsPage(_ data: JSONValue) -> (threads: [AniListThread], hasNextPage: Bool) {
        let threads = data["Page"]["threads"].array.compactMap { parseThread($0) }
        return (threads, data["Page"]["pageInfo"]["hasNextPage"] == .bool(true))
    }

    static func parseThread(_ raw: JSONValue) -> AniListThread? {
        guard let id = raw["id"].integer, let title = raw["title"].string else { return nil }
        return AniListThread(id: id, title: title, body: text(fromHTML: raw["bodyHtml"].string ?? ""),
                             replyCount: raw["replyCount"].integer ?? 0, viewCount: raw["viewCount"].integer ?? 0,
                             isLocked: raw["isLocked"] == .bool(true), isSticky: raw["isSticky"] == .bool(true),
                             createdAt: raw["createdAt"].integer ?? 0, siteURL: raw["siteUrl"].string,
                             author: parseAuthor(raw["user"]))
    }

    static func parseComments(_ data: JSONValue) -> [AniListThreadComment] {
        data["Page"]["threadComments"].array.compactMap { parseComment($0) }
    }

    static func parseComment(_ raw: JSONValue) -> AniListThreadComment? {
        guard let id = raw["id"].integer else { return nil }
        return AniListThreadComment(id: id, text: text(fromHTML: raw["commentHtml"].string ?? ""),
                                    likes: raw["likeCount"].integer ?? 0, isLiked: raw["isLiked"] == .bool(true),
                                    createdAt: raw["createdAt"].integer ?? 0, siteURL: raw["siteUrl"].string,
                                    author: parseAuthor(raw["user"]))
    }

    /// Desktop's `mapUser`: the avatar is the medium picture, else the large one.
    static func parseAuthor(_ raw: JSONValue) -> AniListThreadAuthor {
        let avatar = raw["avatar"]["medium"].string ?? raw["avatar"]["large"].string
        return AniListThreadAuthor(id: raw["id"].integer ?? 0, name: raw["name"].string, avatar: avatar)
    }

    /// Strips the markup of AniList's HTML bodies and decodes the common entities once, `&amp;` last.
    static func text(fromHTML html: String) -> String {
        var text = html.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities: [(String, String)] = [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#039;", "'"), ("&#39;", "'"), ("&nbsp;", " "), ("&amp;", "&")]
        for (entity, value) in entities {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Desktop's `timeAgo` in `anilist-comments.tsx`; `text` translates a key and fills its `{n}`.
    static func ago(unixSeconds: Int, now: Date = Date(), text: (String, Int?) -> String) -> String {
        let minutes = Int(max(0, now.timeIntervalSince1970 - Double(unixSeconds)) / 60)
        if minutes < 1 { return text("just now", nil) }
        if minutes < 60 { return text("{n}m ago", minutes) }
        let hours = minutes / 60
        if hours < 24 { return text("{n}h ago", hours) }
        let days = hours / 24
        if days < 30 { return text("{n}d ago", days) }
        return text("{n}mo ago", days / 30)
    }

    // MARK: Relations

    static func relationEdges(_ data: JSONValue) -> [AniListRelationEdge] {
        data["Media"]["relations"]["edges"].array.map { edge in
            AniListRelationEdge(relationType: edge["relationType"].string, node: parseRelationNode(edge["node"]))
        }
    }

    static func parseRelationNode(_ raw: JSONValue) -> AniListRelationNode? {
        guard let id = raw["id"].integer else { return nil }
        return AniListRelationNode(id: id, format: raw["format"].string, status: raw["status"].string,
                                   english: raw["title"]["english"].string, romaji: raw["title"]["romaji"].string,
                                   userPreferred: raw["title"]["userPreferred"].string, seasonYear: raw["seasonYear"].integer,
                                   startYear: raw["startDate"]["year"].integer, poster: raw["coverImage"]["large"].string)
    }

    /// Desktop's `toNode` name: english, then romaji, then userPreferred (nil-coalescing), trimmed; an empty name is left out.
    static func displayName(_ node: AniListRelationNode) -> String? {
        let raw = (node.english ?? node.romaji ?? node.userPreferred ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw
    }

    /// Desktop's `animeRelations`: breadth-first over PREQUEL and SEQUEL edges. The direction of each step gives the
    /// kind, a node is marked seen before its name is checked, and the limit is checked once per level.
    static func relations(from root: Int, edges: (Int) async -> [AniListRelationEdge]) async -> [AniListRelation] {
        var out: [AniListRelation] = []
        var seen: [Int: Int] = [root: 0]
        var frontier: [(id: Int, direction: Int)] = [(id: root, direction: 0)]
        while !frontier.isEmpty && out.count < maxRelations {
            var batches: [[AniListRelationEdge]] = []
            for item in frontier {
                batches.append(await edges(item.id))
            }
            var next: [(id: Int, direction: Int)] = []
            for (index, item) in frontier.enumerated() {
                for edge in batches[index] {
                    guard let type = edge.relationType, type == "PREQUEL" || type == "SEQUEL", let node = edge.node else { continue }
                    if node.format == "MOVIE" || seen[node.id] != nil { continue }
                    let direction = item.direction + (type == "SEQUEL" ? 1 : -1)
                    seen[node.id] = direction
                    guard let name = displayName(node) else { continue }
                    out.append(AniListRelation(id: node.id, name: name, year: node.seasonYear ?? node.startYear, format: node.format,
                                               poster: node.poster, kind: direction < 0 ? .prequel : .sequel,
                                               upcoming: node.status == "NOT_YET_RELEASED"))
                    next.append((id: node.id, direction: direction))
                }
            }
            frontier = next
        }
        return sortedRelations(out)
    }

    /// Prequels first, newest year first; then sequels, oldest year first. Ties keep their walk order.
    static func sortedRelations(_ list: [AniListRelation]) -> [AniListRelation] {
        list.enumerated().sorted { lhs, rhs -> Bool in
            let left = lhs.element, right = rhs.element
            if left.kind != right.kind { return left.kind == .prequel }
            let leftYear = left.year ?? 0, rightYear = right.year ?? 0
            if leftYear != rightYear { return left.kind == .prequel ? leftYear > rightYear : leftYear < rightYear }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }
}

/// The thread requests of one signed-in viewer. Desktop sends the viewer's token with them.
struct AniListThreadsService: Sendable {
    let client: AniListClient
    let token: String

    func threads(mediaID: Int, page: Int, perPage: Int = 20) async throws -> (threads: [AniListThread], hasNextPage: Bool) {
        let variables: [String: JSONValue] = ["mediaId": .integer(Int64(mediaID)), "page": .integer(Int64(page)), "perPage": .integer(Int64(perPage))]
        let data = try await client.request(AniListThreads.threadsQuery, variables: variables, token: token)
        return AniListThreads.threadsPage(data)
    }

    func comments(threadID: Int) async throws -> [AniListThreadComment] {
        let data = try await client.request(AniListThreads.commentsQuery, variables: ["threadId": .integer(Int64(threadID))], token: token)
        return AniListThreads.parseComments(data)
    }

    /// The AniList id of a Harbor title, through the same lookup the sync uses (`anilist:`, `kitsu:` and `mal:` ids).
    static func anilistID(for harborID: String, token: String) async -> Int? {
        let sync = AniListSync(client: AniListClient(transport: AniListHTTPTransport()), token: token,
                               kitsuToAniList: { await AnimeFranchiseService.shared.anilistMediaID(kitsu: $0) })
        return await sync.mediaID(for: harborID)
    }
}

/// Desktop's `animeRelations` requests. They go out without a token (`skipAuth`), so they work when signed out.
struct AniListRelationsService: Sendable {
    let client: AniListClient

    func relations(anilistID: Int) async -> [AniListRelation] {
        let client = self.client
        return await AniListThreads.relations(from: anilistID) { id in
            guard let data = try? await client.request(AniListThreads.relationsQuery, variables: ["id": .integer(Int64(id))], token: nil) else {
                return []
            }
            return AniListThreads.relationEdges(data)
        }
    }
}
