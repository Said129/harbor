import Foundation

/// Desktop's per-list category pins and hidden categories (`src/lib/iptv/group-order.ts`).
struct LiveGroupPrefs: Codable, Hashable, Sendable {
    var pinned: [String] = []
    var hidden: [String] = []
}

/// Desktop's live channel and category order: `sortChannelsByGroupRelevance` (`group-relevance.ts`),
/// `applyUserChannelOrder` and `applyUserGroupOrder` (`channel-order.ts`), channel pins (`pins.ts`),
/// the group pin and hide toggles (`group-order.ts`), the most-watched order from the play counts (`channel-stats.ts`)
/// and the Favorites group (`favorites.tsx`).
enum LiveTVCatalogOrder {
    /// Desktop's `MOST_WATCHED_MIN`: a channel started this many times moves up after the pinned ones.
    static let mostWatchedMinimum = 3

    /// Desktop's `sortChannelsByGroupRelevance`: higher group score first, then group name, and channels
    /// without a group last. Equal keys keep the source order.
    static func channelsByGroupRelevance(_ channels: [LiveChannel], region: String, preferredLanguages: [String]) -> [LiveChannel] {
        var scores: [String: Int] = [:]
        func score(_ group: String?) -> Int {
            guard let group = group, !group.isEmpty else { return -1 }
            if let cached = scores[group] { return cached }
            let value = LiveTVGroupOrder.score(group, region: region, preferredLanguages: preferredLanguages)
            scores[group] = value
            return value
        }
        let keyed = channels.enumerated().map { (index: $0.offset, channel: $0.element, score: score($0.element.group)) }
        return keyed.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            let left = a.channel.group ?? "", right = b.channel.group ?? ""
            let order = left.localizedCompare(right)
            if order != .orderedSame { return order == .orderedAscending }
            return a.index < b.index
        }.map { $0.channel }
    }

    /// Desktop's `applyUserChannelOrder` without most-watched: pinned channels first, in pin order, then the rest.
    static func pinnedFirst(_ channels: [LiveChannel], pinned: [String]) -> [LiveChannel] {
        guard !channels.isEmpty, !pinned.isEmpty else { return channels }
        var rank: [String: Int] = [:]
        for (index, id) in pinned.enumerated() { rank[id] = index }
        let pinnedRows = channels.enumerated().filter { rank[$0.element.id] != nil }.sorted { lhs, rhs in
            let left = rank[lhs.element.id] ?? 0, right = rank[rhs.element.id] ?? 0
            return left != right ? left < right : lhs.offset < rhs.offset
        }.map { $0.element }
        return pinnedRows + channels.filter { rank[$0.id] == nil }
    }

    /// Desktop's `shownChannels`: channels in hidden categories leave the list. A channel without a group counts as "Uncategorized".
    static func removingHiddenGroups(_ channels: [LiveChannel], hidden: [String]) -> [LiveChannel] {
        guard !hidden.isEmpty else { return channels }
        let hiddenSet = Set(hidden)
        return channels.filter { !hiddenSet.contains($0.group ?? "Uncategorized") }
    }

    /// Desktop's `applyUserChannelOrder`: pinned channels first in pin order, then channels started at least
    /// `mostWatchedMinimum` times (most started first, equal counts keep their order), then the rest in their current order.
    static func userChannelOrder(_ channels: [LiveChannel], pinned: [String], plays: [String: Int]) -> [LiveChannel] {
        guard !channels.isEmpty else { return channels }
        var rank: [String: Int] = [:]
        for (index, id) in pinned.enumerated() { rank[id] = index }
        var pinnedRows: [(index: Int, channel: LiveChannel)] = []
        var watchedRows: [(index: Int, count: Int, channel: LiveChannel)] = []
        var rest: [LiveChannel] = []
        for (index, channel) in channels.enumerated() {
            if rank[channel.id] != nil {
                pinnedRows.append((index: index, channel: channel))
                continue
            }
            let count: Int = plays[channel.id] ?? 0
            if count >= mostWatchedMinimum {
                watchedRows.append((index: index, count: count, channel: channel))
                continue
            }
            rest.append(channel)
        }
        if pinnedRows.isEmpty && watchedRows.isEmpty { return channels }
        let pinnedSorted: [LiveChannel] = pinnedRows.sorted { lhs, rhs in
            let left: Int = rank[lhs.channel.id] ?? 0
            let right: Int = rank[rhs.channel.id] ?? 0
            return left != right ? left < right : lhs.index < rhs.index
        }.map { $0.channel }
        let watchedSorted: [LiveChannel] = watchedRows.sorted { lhs, rhs in
            lhs.count != rhs.count ? lhs.count > rhs.count : lhs.index < rhs.index
        }.map { $0.channel }
        return pinnedSorted + watchedSorted + rest
    }

    /// The channel list order Desktop's pipeline builds: relevance, then pins and most-watched, then hidden categories.
    static func catalog(_ channels: [LiveChannel], region: String, preferredLanguages: [String], pinnedChannels: [String], prefs: LiveGroupPrefs, plays: [String: Int] = [:]) -> [LiveChannel] {
        let relevant: [LiveChannel] = channelsByGroupRelevance(channels, region: region, preferredLanguages: preferredLanguages)
        return removingHiddenGroups(userChannelOrder(relevant, pinned: pinnedChannels, plays: plays), hidden: prefs.hidden)
    }

    /// Desktop's `applyUserGroupOrder`: hidden categories leave the list, pinned categories come first in pin order.
    static func groups(_ groups: [String], prefs: LiveGroupPrefs) -> [String] {
        guard !prefs.pinned.isEmpty || !prefs.hidden.isEmpty else { return groups }
        let hidden = Set(prefs.hidden)
        var rank: [String: Int] = [:]
        for (index, group) in prefs.pinned.enumerated() { rank[group] = index }
        let visible = groups.filter { !hidden.contains($0) }
        let pinned = visible.enumerated().filter { rank[$0.element] != nil }.sorted { lhs, rhs in
            let left = rank[lhs.element] ?? 0, right = rank[rhs.element] ?? 0
            return left != right ? left < right : lhs.offset < rhs.offset
        }.map { $0.element }
        return pinned + visible.filter { rank[$0] == nil }
    }

    /// Desktop's `toggleGroupPin`: pinning removes a hide; unpinning keeps the category visible.
    static func togglingPin(_ prefs: LiveGroupPrefs, group: String) -> LiveGroupPrefs {
        var next = prefs
        if next.pinned.contains(group) { next.pinned.removeAll { $0 == group } } else { next.pinned.append(group) }
        next.hidden.removeAll { $0 == group }
        return next
    }

    /// Desktop's `toggleGroupHidden`: hiding removes a pin.
    static func togglingHidden(_ prefs: LiveGroupPrefs, group: String) -> LiveGroupPrefs {
        var next = prefs
        next.pinned.removeAll { $0 == group }
        if next.hidden.contains(group) { next.hidden.removeAll { $0 == group } } else { next.hidden.append(group) }
        return next
    }

    /// Desktop's `togglePin` for channels: the pinned ids keep the order in which they were pinned.
    static func togglingChannelPin(_ pinned: [String], channelID: String) -> [String] {
        pinned.contains(channelID) ? pinned.filter { $0 != channelID } : pinned + [channelID]
    }

    /// Desktop's `favoriteChannels`: favourites with a stream URL, ordered by source name and then channel name.
    /// Each one shows its source name as its category, so a favourite stays listed when its playlist is not loaded.
    static func favoriteChannels(_ items: [LiveChannel], sourceNames: [String: String]) -> [LiveChannel] {
        items.filter { !$0.url.isEmpty }.sorted { a, b in
            let left = sourceNames[a.source] ?? a.source, right = sourceNames[b.source] ?? b.source
            let order = left.localizedCompare(right)
            if order != .orderedSame { return order == .orderedAscending }
            return a.name.localizedCompare(b.name) == .orderedAscending
        }.map { channel in
            LiveChannel(id: channel.id, source: channel.source, tvgID: channel.tvgID, name: channel.name, logo: channel.logo, group: sourceNames[channel.source] ?? "Favorites", url: channel.url, catchup: channel.catchup, duration: channel.duration, attributes: channel.attributes)
        }
    }
}
