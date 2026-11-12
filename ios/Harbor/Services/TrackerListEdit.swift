import Foundation

/// Desktop's list edits (`views/library/anilist-tab.tsx`, `views/library/mal-tab.tsx`, `lib/anilist/mutations.ts`,
/// `lib/mal/mutations.ts`): a list entry's status can change, its episode count can move forward, or the entry can be
/// removed from the card's menu. Each call is one request and the caller reloads the list afterwards.
/// One status in an entry menu: the list status and the Desktop label shown for it.
struct TrackerStatusChoice<Status: Hashable & Sendable>: Equatable, Sendable {
    let status: Status
    let label: String
}

enum TrackerListEdit {
    /// The episode count after one more episode, or nil when the title is already complete. The count never passes a known total.
    static func nextProgress(_ current: Int, total: Int?) -> Int? {
        if let total, total > 0 {
            return current < total ? current + 1 : nil
        }
        return current + 1
    }

    /// The AniList statuses in Desktop's order, with their Desktop labels.
    static let aniListChoices: [TrackerStatusChoice<AniListListStatus>] = [
        TrackerStatusChoice(status: .current, label: "Current"), TrackerStatusChoice(status: .planning, label: "Planning"),
        TrackerStatusChoice(status: .completed, label: "Completed"), TrackerStatusChoice(status: .paused, label: "Paused"),
        TrackerStatusChoice(status: .dropped, label: "Dropped"), TrackerStatusChoice(status: .repeating, label: "Repeating"),
    ]

    /// The MyAnimeList statuses in Desktop's order, with their Desktop labels.
    static let malChoices: [TrackerStatusChoice<MALListStatus>] = [
        TrackerStatusChoice(status: .watching, label: "Watching"), TrackerStatusChoice(status: .planToWatch, label: "Plan to Watch"),
        TrackerStatusChoice(status: .completed, label: "Completed"), TrackerStatusChoice(status: .onHold, label: "On Hold"),
        TrackerStatusChoice(status: .dropped, label: "Dropped"),
    ]

    static let aniListSaveQuery = "mutation ($mediaId: Int, $status: MediaListStatus) { SaveMediaListEntry(mediaId: $mediaId, status: $status) { id status progress } }"
    static let aniListProgressQuery = "mutation ($mediaId: Int, $progress: Int) { SaveMediaListEntry(mediaId: $mediaId, progress: $progress) { id status progress } }"
    static let aniListEntryQuery = "query ($mediaId: Int) { Media(id: $mediaId, type: ANIME) { mediaListEntry { id } } }"
    static let aniListDeleteQuery = "mutation ($id: Int) { DeleteMediaListEntry(id: $id) { deleted } }"

    /// Sets the AniList status of one title; AniList creates the entry when it is missing.
    static func aniListSave(mediaID: Int, status: AniListListStatus, token: String, client: AniListClient) async throws {
        let variables: [String: JSONValue] = ["mediaId": .integer(Int64(mediaID)), "status": .string(status.rawValue)]
        _ = try await client.request(aniListSaveQuery, variables: variables, token: token)
    }

    /// Sets the AniList episode count of one title.
    static func aniListProgress(mediaID: Int, progress: Int, token: String, client: AniListClient) async throws {
        let variables: [String: JSONValue] = ["mediaId": .integer(Int64(mediaID)), "progress": .integer(Int64(progress))]
        _ = try await client.request(aniListProgressQuery, variables: variables, token: token)
    }

    /// Removes a title's AniList entry. AniList deletes by entry id, so the id is looked up first.
    static func aniListRemove(mediaID: Int, token: String, client: AniListClient) async throws {
        let found = try await client.request(aniListEntryQuery, variables: ["mediaId": .integer(Int64(mediaID))], token: token)
        guard let entryID = found["Media"]["mediaListEntry"]["id"].integer else { return }
        _ = try await client.request(aniListDeleteQuery, variables: ["id": .integer(Int64(entryID))], token: token)
    }

    /// Sets the MyAnimeList status of one title; MyAnimeList creates the entry when it is missing.
    static func malSave(mediaID: Int, status: MALListStatus, token: String, client: MALClient) async throws {
        _ = try await client.request("/anime/\(mediaID)/my_list_status", method: "PUT", form: [("status", status.rawValue)], token: token)
    }

    /// Sets the MyAnimeList episode count of one title.
    static func malProgress(mediaID: Int, watched: Int, token: String, client: MALClient) async throws {
        _ = try await client.request("/anime/\(mediaID)/my_list_status", method: "PUT", form: [("num_watched_episodes", String(watched))], token: token)
    }

    /// Removes a title from the MyAnimeList list.
    static func malRemove(mediaID: Int, token: String, client: MALClient) async throws {
        _ = try await client.request("/anime/\(mediaID)/my_list_status", method: "DELETE", token: token)
    }
}
