import Foundation

/// Desktop's region "Top networks" for Live TV: `src/lib/iptv/top-networks.ts`, used by
/// `src/views/live/top-networks-rows.tsx`. Each network has a regex matched against "name group",
/// the best-scoring channel per network wins (a channel can only back one network), and the
/// networks are listed per row in table order.
struct LiveTVNetworkDef: Identifiable {
    let id: String
    let displayName: String
    let match: NSRegularExpression?
    let exclude: NSRegularExpression?
}

struct LiveTVNetworkRow: Identifiable {
    let id: String
    let title: String
    let networks: [LiveTVNetworkDef]
}

struct LiveTVResolvedNetwork: Identifiable {
    let def: LiveTVNetworkDef
    let channel: LiveChannel
    var id: String { def.id }
}

struct LiveTVNetworkSection: Identifiable {
    let id: String
    let title: String
    let networks: [LiveTVResolvedNetwork]
}

enum LiveTVRegionNetworks {
    // MARK: Rows per region

    static func rows(for region: String) -> [LiveTVNetworkRow] {
        switch region.uppercased() {
        case "US", "USA": return usRows
        case "BR", "BRA": return brRows
        case "GB", "UK": return ukRows
        default: return []
        }
    }

    /// `resolveNetworks` per row, keeping only rows with at least one network on the channel list.
    static func sections(region: String, channels: [LiveChannel]) -> [LiveTVNetworkSection] {
        var out: [LiveTVNetworkSection] = []
        for row in rows(for: region) {
            let resolved = resolve(channels, defs: row.networks)
            if resolved.isEmpty { continue }
            out.append(LiveTVNetworkSection(id: row.id, title: row.title, networks: resolved))
        }
        return out
    }

    // MARK: Channel resolution

    /// `resolveNetworks`: for each network in order, the highest-scoring unclaimed channel whose
    /// "name group" matches and whose "name group" does not match the exclusion.
    static func resolve(_ channels: [LiveChannel], defs: [LiveTVNetworkDef]) -> [LiveTVResolvedNetwork] {
        var out: [LiveTVResolvedNetwork] = []
        var claimed = Set<String>()
        for def in defs {
            var best: LiveChannel?
            var bestScore = -Double.infinity
            for channel in channels where !claimed.contains(channel.id) {
                let haystack = channel.name + " " + (channel.group ?? "")
                if test(def.exclude, haystack) { continue }
                guard test(def.match, haystack) else { continue }
                let value = score(channel, def)
                if value > bestScore {
                    bestScore = value
                    best = channel
                }
            }
            guard let winner = best else { continue }
            claimed.insert(winner.id)
            out.append(LiveTVResolvedNetwork(def: def, channel: winner))
        }
        return out
    }

    /// `promoteTopChannelsToFront`: resolved network channels first, then the rest in list order.
    static func promoteToFront(_ channels: [LiveChannel], rows: [LiveTVNetworkRow], candidates: [LiveChannel]? = nil) -> [LiveChannel] {
        guard !rows.isEmpty else { return channels }
        let resolved = resolve(candidates ?? channels, defs: rows.flatMap { $0.networks })
        guard !resolved.isEmpty else { return channels }
        let promoted = Set(resolved.map { $0.channel.id })
        return resolved.map { $0.channel } + channels.filter { !promoted.contains($0.id) }
    }

    /// `filterChannelsByRegion`: channels whose group carries a region token (`\bUS\b` etc.).
    /// Unknown regions return every channel.
    static func filterByRegion(_ channels: [LiveChannel], region: String) -> [LiveChannel] {
        guard let tokens = regionGroupTokens[region.uppercased()] else { return channels }
        let patterns = tokens.compactMap { compile("\\b" + $0 + "\\b", caseInsensitive: false) }
        return channels.filter { channel in
            let group = (channel.group ?? "").uppercased()
            guard !group.isEmpty else { return false }
            return patterns.contains { test($0, group) }
        }
    }

    private static let regionGroupTokens: [String: [String]] = [
        "US": ["US", "USA", "AMERICAN"],
        "USA": ["US", "USA", "AMERICAN"],
        "BR": ["BR", "BRA", "BRASIL", "BRAZIL"],
        "BRA": ["BR", "BRA", "BRASIL", "BRAZIL"],
        "GB": ["UK", "GB", "BRITAIN", "BRITISH", "ENGLAND"],
        "UK": ["UK", "GB", "BRITAIN", "BRITISH", "ENGLAND"],
    ]

    // MARK: Scoring (`scoreChannel`)

    private static func score(_ channel: LiveChannel, _ def: LiveTVNetworkDef) -> Double {
        let name = channel.name
        var value = 100.0
        if test(def.match, name) { value += 30 }
        if test(parenthesis, name) { value -= 25 }
        if test(bracketedCode, name) { value -= 12 }
        if test(quality, name) { value += 5 }
        if test(direction, name) { value += 3 }
        if test(twentyFourSeven, name) { value -= 8 }
        if test(newYork, name) { value += 22 }
        if test(national, name) { value += 30 }
        if test(losAngeles, name) { value += 12 }
        if test(liveNow, name) { value -= 30 }
        if test(backupFeed, name) { value -= 25 }
        if test(alternate, name) { value -= 20 }
        if test(streamNumber, name) { value -= 15 }
        if test(testWord, name) { value -= 30 }
        value -= Double(name.utf16.count) * 0.05
        return value
    }

    private static let parenthesis = compile(#"\("#, caseInsensitive: false)
    private static let bracketedCode = compile(#"\s[A-Z]{2}\s"#, caseInsensitive: false)
    private static let quality = compile(#"\b(HD|FHD|UHD|4K)\b"#)
    private static let direction = compile(#"east\s+coast|west\s+coast|east|west"#)
    private static let twentyFourSeven = compile(#"24/7"#)
    private static let newYork = compile(#"\b(NEW YORK|NYC)\b"#)
    private static let national = compile(#"\bNATIONAL\b"#)
    private static let losAngeles = compile(#"\b(LOS ANGELES|LA)\b"#)
    private static let liveNow = compile(#"\blive\s+now\b"#)
    private static let backupFeed = compile(#"\b(raw|backup|feed|mirror|secondary)\b"#)
    private static let alternate = compile(#"\balt\b|\baltern"#)
    private static let streamNumber = compile(#"\bstream\s*\d+\b|\bs\d+\b"#)
    private static let testWord = compile(#"\b(test|tmp|temp)\b"#)

    // MARK: Regex helpers

    private static func compile(_ pattern: String, caseInsensitive: Bool = true) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
    }

    private static func test(_ regex: NSRegularExpression?, _ text: String) -> Bool {
        guard let regex = regex else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// Desktop's `word()`: the term bounded by non-alphanumerics (ASCII) or the ends of the text.
    private static func word(_ term: String) -> String {
        "(?:^|[^a-z0-9])" + term + "(?:$|[^a-z0-9])"
    }

    private static func def(_ id: String, _ name: String, _ match: String, exclude: String? = nil) -> LiveTVNetworkDef {
        LiveTVNetworkDef(id: id, displayName: name, match: compile(match), exclude: exclude.flatMap { compile($0) })
    }

    // MARK: United States

    private static let usBroadcast = LiveTVNetworkRow(id: "us-broadcast", title: "Broadcast networks", networks: [
        def("abc", "ABC", word("abc"), exclude: #"family|news\s|abcn\b|spark"#),
        def("cbs", "CBS", word("cbs"), exclude: #"sports|news\s|cbsn\b|justice"#),
        def("nbc", "NBC", word("nbc"), exclude: #"msnbc|cnbc|sports|news\s"#),
        def("fox", "FOX", word("fox"), exclude: #"fox\s+news|fox\s+sports|fox\s+business|news\s"#),
        def("cw", "The CW", #"\bcw\b"#, exclude: #"cwseed|news\s"#),
        def("pbs", "PBS", #"\bpbs\b"#, exclude: #"kids|news\s"#),
        def("my-network", "MyNetwork", #"mynetwork"#),
        def("telemundo", "Telemundo", #"telemundo"#),
        def("univision", "Univision", #"univision"#, exclude: #"tudn"#),
        def("estrella", "Estrella TV", #"estrella"#),
    ])

    private static let usNews = LiveTVNetworkRow(id: "us-news", title: "News", networks: [
        def("cnn", "CNN", #"\bcnn\b"#, exclude: #"cnn\s+espanol"#),
        def("fox-news", "FOX News", #"fox\s+news"#),
        def("msnbc", "MSNBC", #"msnbc"#),
        def("cnbc", "CNBC", #"\bcnbc\b"#, exclude: #"world"#),
        def("fox-business", "FOX Business", #"fox\s+business"#),
        def("newsmax", "Newsmax", #"newsmax"#),
        def("oan", "OAN", #"\boan\b|one\s+america\s+news"#),
        def("newsnation", "NewsNation", #"newsnation"#),
        def("bbc-america", "BBC America", #"bbc\s+america"#),
        def("bbc-world", "BBC World", #"bbc\s+world"#),
        def("bloomberg", "Bloomberg", #"bloomberg"#),
        def("weather", "Weather Channel", #"weather\s+channel"#),
        def("c-span", "C-SPAN", #"\bc[\s-]?span\b"#),
    ])

    private static let usSports = LiveTVNetworkRow(id: "us-sports", title: "Sports", networks: [
        def("espn", "ESPN", #"\bespn\b"#, exclude: #"espn2|espnu|espn\s+news|espn\s+deportes|espn\+|espn\s+plus"#),
        def("espn2", "ESPN2", #"\bespn2\b"#),
        def("espn-u", "ESPNU", #"\bespnu\b"#),
        def("espn-news", "ESPN News", #"espn\s+news"#),
        def("espn-deportes", "ESPN Deportes", #"espn\s+deportes"#),
        def("espn-plus", "ESPN+", #"espn\+|espn\s+plus"#),
        def("fs1", "FOX Sports 1", #"fox\s+sports\s+1|\bfs1\b"#),
        def("fs2", "FOX Sports 2", #"fox\s+sports\s+2|\bfs2\b"#),
        def("nbc-sports", "NBC Sports", #"nbc\s+sports"#),
        def("cbs-sports", "CBS Sports", #"cbs\s+sports"#),
        def("nfl-network", "NFL Network", #"\bnfl\s+network\b"#),
        def("nfl-redzone", "NFL RedZone", #"redzone"#),
        def("nba-tv", "NBA TV", #"\bnba\s+tv\b"#),
        def("mlb", "MLB Network", #"\bmlb\s+network\b"#),
        def("nhl", "NHL Network", #"\bnhl\s+network\b"#),
        def("tennis", "Tennis Channel", #"tennis\s+channel"#),
        def("golf", "Golf Channel", #"golf\s+channel"#),
        def("btn", "Big Ten Network", #"big\s+ten\s+network|\bbtn\+?\b"#),
        def("sec", "SEC Network", #"sec\s+network"#),
        def("acc", "ACC Network", #"acc\s+network"#),
        def("olympic", "Olympic Channel", #"olympic\s+channel"#),
        def("tudn", "TUDN", #"\btudn\b"#),
    ])

    private static let usPremium = LiveTVNetworkRow(id: "us-premium", title: "Premium movies", networks: [
        def("hbo", "HBO", #"\bhbo\b"#, exclude: #"max|latino|hits"#),
        def("max", "Max", #"hbo\s+max|\bmax\b"#, exclude: #"cinemax|maxim"#),
        def("showtime", "Showtime", #"showtime"#),
        def("starz", "Starz", #"starz"#, exclude: #"encore"#),
        def("cinemax", "Cinemax", #"cinemax"#),
        def("epix", "MGM+", #"\bepix\b|mgm\+|mgm\s+plus"#),
        def("paramount-plus", "Paramount+", #"paramount\+|paramount\s+plus"#),
        def("peacock", "Peacock", #"peacock"#),
        def("apple-tv-plus", "Apple TV+", #"apple\s+tv\+|apple\s+tv\s+plus"#),
        def("disney-plus", "Disney+", #"disney\+|disney\s+plus"#, exclude: #"channel|jr|xd"#),
        def("netflix", "Netflix", #"netflix"#),
        def("tcm", "Turner Classic Movies", #"turner\s+classic|\btcm\b"#),
    ])

    private static let usEntertainment = LiveTVNetworkRow(id: "us-entertainment", title: "Entertainment", networks: [
        def("amc", "AMC", #"\bamc\b"#, exclude: #"\+|plus"#),
        def("fx", "FX", #"\bfx\b"#, exclude: #"fxx|fxm|fox"#),
        def("fxx", "FXX", #"\bfxx\b"#),
        def("fxm", "FXM", #"\bfxm\b"#),
        def("usa", "USA Network", #"usa\s+network"#),
        def("tnt", "TNT", #"\btnt\b"#, exclude: #"sports"#),
        def("tbs", "TBS", #"\btbs\b"#),
        def("bravo", "Bravo", #"\bbravo\b"#),
        def("e", "E!", #"\be!\s|^e!$|\be!\stv"#),
        def("syfy", "SyFy", #"sy[\s-]?fy"#),
        def("comedy-central", "Comedy Central", #"comedy\s+central"#),
        def("paramount-network", "Paramount Network", #"paramount\s+network"#),
        def("ifc", "IFC", #"\bifc\b"#),
        def("sundance", "Sundance", #"sundance"#),
        def("pop-tv", "Pop TV", #"\bpop\s+tv\b"#),
        def("we-tv", "WE tv", #"\bwe\s+tv\b"#),
        def("ovation", "Ovation", #"ovation"#),
        def("reelz", "Reelz", #"reelz"#),
    ])

    private static let usLifestyle = LiveTVNetworkRow(id: "us-lifestyle", title: "Lifestyle & Reality", networks: [
        def("hgtv", "HGTV", #"\bhgtv\b"#),
        def("food", "Food Network", #"food\s+network"#),
        def("tlc", "TLC", #"\btlc\b"#),
        def("lifetime", "Lifetime", #"\blifetime\b"#, exclude: #"movies"#),
        def("lifetime-movies", "Lifetime Movies", #"lifetime\s+movies"#),
        def("own", "OWN", #"\bown\b"#),
        def("ae", "A&E", #"\ba[\s&]+e\b|a\s*&\s*e"#),
        def("investigation", "Investigation Discovery", #"investigation\s+discovery|\bid\b\s+channel"#),
        def("hallmark", "Hallmark", #"hallmark"#, exclude: #"movies|drama"#),
        def("hallmark-movies", "Hallmark Movies", #"hallmark\s+movies"#),
        def("diy", "DIY", #"\bdiy\b"#),
        def("magnolia", "Magnolia", #"magnolia"#),
        def("fyi", "FYI", #"\bfyi\b"#),
    ])

    private static let usDocumentary = LiveTVNetworkRow(id: "us-documentary", title: "Documentary & Discovery", networks: [
        def("discovery", "Discovery", #"discovery"#, exclude: #"science|family|investigation|history"#),
        def("history", "History", #"\bhistory\b"#, exclude: #"military|vault"#),
        def("history2", "History 2", #"history\s+2|h2\b"#),
        def("natgeo", "Nat Geo", #"nat\s*geo|national\s+geographic"#, exclude: #"wild|mundo"#),
        def("natgeo-wild", "Nat Geo Wild", #"nat\s*geo\s+wild"#),
        def("smithsonian", "Smithsonian", #"smithsonian"#),
        def("science", "Science Channel", #"science\s+channel"#),
        def("animal-planet", "Animal Planet", #"animal\s+planet"#),
        def("travel", "Travel Channel", #"travel\s+channel"#),
        def("destination", "Destination America", #"destination\s+america"#),
        def("motortrend", "MotorTrend", #"motor\s*trend"#),
    ])

    private static let usKids = LiveTVNetworkRow(id: "us-kids", title: "Kids & Family", networks: [
        def("disney", "Disney Channel", #"disney\s+channel"#),
        def("disney-jr", "Disney Jr", #"disney\s+jr"#),
        def("disney-xd", "Disney XD", #"disney\s+xd"#),
        def("nickelodeon", "Nickelodeon", #"nickelodeon"#, exclude: #"jr|nicktoons"#),
        def("nick-jr", "Nick Jr", #"nick\s+jr"#),
        def("nicktoons", "Nicktoons", #"nicktoons"#),
        def("cartoon-network", "Cartoon Network", #"cartoon\s+network"#),
        def("boomerang", "Boomerang", #"boomerang"#),
        def("pbs-kids", "PBS Kids", #"pbs\s+kids"#),
        def("universal-kids", "Universal Kids", #"universal\s+kids"#),
        def("cartoonito", "Cartoonito", #"cartoonito"#),
        def("baby-tv", "Baby TV", #"baby\s*tv"#),
    ])

    private static let usMusic = LiveTVNetworkRow(id: "us-music", title: "Music", networks: [
        def("mtv", "MTV", #"\bmtv\b"#, exclude: #"mtv2|live|classic"#),
        def("mtv2", "MTV2", #"\bmtv2\b"#),
        def("mtv-classic", "MTV Classic", #"mtv\s+classic"#),
        def("mtv-live", "MTV Live", #"mtv\s+live"#),
        def("vh1", "VH1", #"\bvh1\b"#),
        def("bet", "BET", #"\bbet\b"#, exclude: #"her"#),
        def("bet-her", "BET Her", #"bet\s+her"#),
        def("cmt", "CMT", #"\bcmt\b"#),
        def("revolt", "Revolt", #"revolt"#),
        def("axs", "AXS TV", #"\baxs\s+tv\b"#),
    ])

    private static let usRows: [LiveTVNetworkRow] = [
        usBroadcast, usNews, usSports, usPremium, usEntertainment, usLifestyle, usDocumentary, usKids, usMusic,
    ]

    // MARK: Brazil

    private static let brBroadcast = LiveTVNetworkRow(id: "br-broadcast", title: "Rede aberta", networks: [
        def("globo", "Globo", #"\bglobo\b"#, exclude: #"news|esporte"#),
        def("globonews", "GloboNews", #"globo\s*news"#),
        def("sbt", "SBT", #"\bsbt\b"#),
        def("record", "Record", #"\brecord\b"#, exclude: #"news"#),
        def("record-news", "Record News", #"record\s+news"#),
        def("band", "Band", #"\bband\b"#, exclude: #"sports|news"#),
        def("redetv", "RedeTV!", #"redetv"#),
        def("cnn-brasil", "CNN Brasil", #"cnn\s+brasil"#),
    ])

    private static let brSports = LiveTVNetworkRow(id: "br-sports", title: "Esportes", networks: [
        def("sportv", "SporTV", #"sportv"#),
        def("espn-br", "ESPN Brasil", #"espn\s+brasil"#),
        def("premiere", "Premiere", #"premiere"#),
        def("combate", "Combate", #"combate"#),
        def("esporte-interativo", "Esporte Interativo", #"esporte\s+interativo"#),
    ])

    private static let brRows: [LiveTVNetworkRow] = [brBroadcast, brSports]

    // MARK: United Kingdom

    private static let ukBroadcast = LiveTVNetworkRow(id: "uk-broadcast", title: "Broadcast", networks: [
        def("bbc-one", "BBC One", #"bbc\s+one"#),
        def("bbc-two", "BBC Two", #"bbc\s+two"#),
        def("bbc-three", "BBC Three", #"bbc\s+three"#),
        def("bbc-four", "BBC Four", #"bbc\s+four"#),
        def("itv", "ITV", #"\bitv\b"#),
        def("channel-4", "Channel 4", #"channel\s+4"#),
        def("channel-5", "Channel 5", #"channel\s+5"#),
        def("sky-news", "Sky News", #"sky\s+news"#),
    ])

    private static let ukSports = LiveTVNetworkRow(id: "uk-sports", title: "Sports", networks: [
        def("sky-sports", "Sky Sports", #"sky\s+sports"#),
        def("bt-sport", "BT Sport", #"\bbt\s+sport\b"#),
        def("tnt-sports-uk", "TNT Sports", #"tnt\s+sports"#),
        def("eurosport", "Eurosport", #"eurosport"#),
    ])

    private static let ukRows: [LiveTVNetworkRow] = [ukBroadcast, ukSports]
}
