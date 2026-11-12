import Foundation

/// Desktop's XMLTV reader (`src/lib/iptv/xmltv.ts`): channel display names and programmes, the same 200 MB cap,
/// the same XMLTV time rules, and the same rule that drops a programme without a usable channel and window.
/// A gzip-compressed guide is inflated with zlib (Desktop's `DecompressionStream("gzip")`).
enum LiveTVXMLTV {
    /// Desktop's `MAX_BYTES`.
    static let maximumBytes = 200 * 1024 * 1024

    /// iOS keeps the bounded Desktop guide window for now-next and catch-up. The service passes that time range so a
    /// big guide does not fill the phone's memory with unbounded history; nil keeps every programme, as Desktop does.
    static func parse(_ data: Data, window: ClosedRange<Date>? = nil) throws -> LiveTVGuide {
        guard data.count <= maximumBytes else { throw HarborError(code: "iptv-size") }
        var xml = data
        if isGzip(data) { xml = try gunzip(data) }
        let delegate = LiveTVXMLTVDelegate()
        delegate.window = window.map { $0.lowerBound.timeIntervalSince1970...$0.upperBound.timeIntervalSince1970 }
        let parser = XMLParser(data: xml)
        parser.shouldProcessNamespaces = false
        parser.delegate = delegate
        let finished = parser.parse()
        // Desktop tolerates broken markup; XMLParser stops at the first error, so keep what was read before it.
        if !finished, delegate.programs.isEmpty, delegate.channelOrder.isEmpty { throw HarborError(code: "iptv-format") }
        return LiveTVGuide(programs: delegate.programs, displayNames: delegate.displayNames, channelOrder: delegate.channelOrder, programOrder: delegate.programOrder)
    }

    static func isGzip(_ data: Data) -> Bool {
        data.count >= 2 && data[data.startIndex] == 0x1f && data[data.startIndex + 1] == 0x8b
    }

    /// Inflates a gzip body with zlib (`Harbor-Bridging-Header.h` imports zlib.h and project.yml links libz).
    /// windowBits 15 + 32 reads the gzip header itself. The output stops at `maximumBytes`, like Desktop's cap.
    static func gunzip(_ data: Data) throws -> Data {
        var stream = z_stream()
        guard inflateInit2_(&stream, 15 + 32, zlibVersion(), Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw HarborError(code: "iptv-format")
        }
        defer { _ = inflateEnd(&stream) }
        var input = [UInt8](data)
        var output = Data()
        var finished = false
        var failed = false
        input.withUnsafeMutableBufferPointer { inputBuffer in
            stream.next_in = inputBuffer.baseAddress
            stream.avail_in = uInt(inputBuffer.count)
            var chunk = [UInt8](repeating: 0, count: 256 * 1024)
            while !finished && !failed {
                chunk.withUnsafeMutableBufferPointer { outputBuffer in
                    stream.next_out = outputBuffer.baseAddress
                    stream.avail_out = uInt(outputBuffer.count)
                    let code = inflate(&stream, Z_NO_FLUSH)
                    let produced = outputBuffer.count - Int(stream.avail_out)
                    if produced > 0, let base = outputBuffer.baseAddress { output.append(base, count: produced) }
                    if code == Z_STREAM_END {
                        finished = true
                    } else if code != Z_OK || (produced == 0 && stream.avail_in == 0) {
                        failed = true
                    }
                }
                if output.count > maximumBytes { failed = true }
            }
        }
        guard finished, !failed else { throw HarborError(code: output.count > maximumBytes ? "iptv-size" : "iptv-format") }
        return output
    }

    private static let timePattern = try! NSRegularExpression(pattern: #"^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})\s*([+-]\d{4})?"#)

    /// Desktop's `parseXmltvTime`: `YYYYMMDDhhmmss`, read as UTC unless a `+hhmm` or `-hhmm` offset follows. Nil when not a time.
    static func parseTime(_ raw: String) -> TimeInterval? {
        guard let match = timePattern.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)) else { return nil }
        func part(_ index: Int) -> Int? { Range(match.range(at: index), in: raw).flatMap { Int(raw[$0]) } }
        guard let year = part(1), let month = part(2), let day = part(3), let hour = part(4), let minute = part(5), let second = part(6) else { return nil }
        var offsetMinutes = 0
        if let zone = Range(match.range(at: 7), in: raw) {
            let text = raw[zone]
            let sign = text.first == "-" ? -1 : 1
            let hours = Int(text.dropFirst().prefix(2)) ?? 0
            let minutes = Int(text.dropFirst(3).prefix(2)) ?? 0
            offsetMinutes = sign * (hours * 60 + minutes)
        }
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.hour = hour; components.minute = minute; components.second = second
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        guard let utc = calendar.date(from: components) else { return nil }
        return utc.timeIntervalSince1970 - TimeInterval(offsetMinutes * 60)
    }
}

/// A parsed XMLTV guide. Programmes are keyed by the XMLTV channel id and sorted by start.
struct LiveTVGuide: Sendable {
    let programs: [String: [LiveProgram]]
    /// Desktop's `channelMeta.displayName`, keyed by the XMLTV channel id.
    let displayNames: [String: String]
    /// Desktop's `nameIndexFor`: the first id for each normalised name. Channel display names come before programme ids.
    let nameIndex: [String: String]

    init(programs: [String: [LiveProgram]], displayNames: [String: String], channelOrder: [String], programOrder: [String]) {
        self.programs = programs.mapValues { $0.sorted { $0.start < $1.start } }
        self.displayNames = displayNames
        var index: [String: String] = [:]
        for id in channelOrder {
            guard let name = displayNames[id] else { continue }
            let key = LiveTVGuideLookup.nameKey(name)
            if !key.isEmpty, index[key] == nil { index[key] = id }
        }
        for id in programOrder {
            let key = LiveTVGuideLookup.nameKey(id)
            if !key.isEmpty, index[key] == nil { index[key] = id }
        }
        nameIndex = index
    }

    var isEmpty: Bool { programs.isEmpty }
}

private final class LiveTVXMLTVDelegate: NSObject, XMLParserDelegate {
    private(set) var programs: [String: [LiveProgram]] = [:]
    private(set) var programOrder: [String] = []
    private(set) var displayNames: [String: String] = [:]
    private(set) var channelOrder: [String] = []
    private var seenChannels = Set<String>()
    private var programmeCount = 0
    /// When set, a programme that ends before the window or starts after it is not kept.
    var window: ClosedRange<TimeInterval>?

    private var channelID: String?
    private var channelName: String?
    private var channelNameDone = false

    private var programme: (channel: String, start: TimeInterval, end: TimeInterval)?
    private var title: String?
    private var programmeDescription: String?
    private var titleDone = false
    private var descriptionDone = false

    /// The element whose text is being collected: "display-name", "title" or "desc".
    private var textTarget: String?
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        switch elementName {
        case "channel":
            channelID = attributeDict["id"].flatMap { $0.isEmpty ? nil : $0 }
            channelName = nil
            channelNameDone = false
        case "display-name":
            guard channelID != nil, !channelNameDone else { return }
            textTarget = elementName; text = ""
        case "programme":
            programme = nil; title = nil; programmeDescription = nil; titleDone = false; descriptionDone = false
            guard let channel = attributeDict["channel"], !channel.isEmpty,
                  let startRaw = attributeDict["start"], !startRaw.isEmpty,
                  let stopRaw = attributeDict["stop"], !stopRaw.isEmpty,
                  let start = LiveTVXMLTV.parseTime(startRaw), let end = LiveTVXMLTV.parseTime(stopRaw),
                  start.isFinite, end.isFinite, end > start else { return }
            programme = (channel: channel, start: start, end: end)
        case "title":
            guard programme != nil, !titleDone else { return }
            textTarget = elementName; text = ""
        case "desc":
            guard programme != nil, !descriptionDone else { return }
            textTarget = elementName; text = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if textTarget != nil { text += string }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if textTarget != nil, let string = String(data: CDATABlock, encoding: .utf8) { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if let target = textTarget, target == elementName {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            textTarget = nil; text = ""
            switch target {
            case "display-name":
                channelName = value.isEmpty ? nil : value
                channelNameDone = true
            case "title":
                title = value.isEmpty ? "Untitled" : value
                titleDone = true
            default:
                programmeDescription = value.isEmpty ? nil : value
                descriptionDone = true
            }
        }
        switch elementName {
        case "channel": storeChannel()
        case "programme": storeProgramme()
        default: break
        }
    }

    private func storeChannel() {
        defer { channelID = nil; channelName = nil; channelNameDone = false }
        guard let id = channelID else { return }
        // Desktop keeps an earlier entry when a repeated channel has no display name.
        if seenChannels.contains(id), channelName == nil { return }
        if seenChannels.insert(id).inserted { channelOrder.append(id) }
        displayNames[id] = channelName
    }

    private func storeProgramme() {
        defer { programme = nil; title = nil; programmeDescription = nil; titleDone = false; descriptionDone = false }
        guard let entry = programme else { return }
        if let window, entry.end < window.lowerBound || entry.start > window.upperBound { return }
        programmeCount += 1
        let program = LiveProgram(
            id: "\(entry.channel)|\(Int(entry.start))|\(programmeCount)",
            title: title ?? "Untitled",
            description: programmeDescription,
            start: Date(timeIntervalSince1970: entry.start),
            end: Date(timeIntervalSince1970: entry.end)
        )
        if programs[entry.channel] == nil { programOrder.append(entry.channel) }
        programs[entry.channel, default: []].append(program)
    }
}
