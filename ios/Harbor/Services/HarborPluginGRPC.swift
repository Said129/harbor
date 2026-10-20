import Foundation

enum HarborPluginGRPCError: String, Error, LocalizedError, Sendable {
    case invalidBase64 = "invalid base64 protobuf request"
    case tooLarge = "protobuf request exceeds 8 MB"
    case incompleteHeader = "incomplete gRPC frame header"
    case incompletePayload = "incomplete gRPC frame payload"
    case trailerFlags = "invalid gRPC trailer frame flags"
    case messageFlags = "invalid gRPC message frame flags"
    case compressed = "compressed gRPC responses are not supported"
    var errorDescription: String? { rawValue }
}

/// Wire framing from the pinned host-http.ts. This codec performs no network requests.
enum HarborPluginGRPC {
    static let maximumBytes = 8 * 1024 * 1024
    private static let whitespace = CharacterSet(charactersIn: " \t\n\r\u{000b}\u{000c}\u{00a0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200a}\u{2028}\u{2029}\u{202f}\u{205f}\u{3000}\u{feff}")

    static func requestFrame(_ base64: String) throws -> Data {
        var text = base64.components(separatedBy: whitespace).joined()
        // atob accepts unpadded input, but rejects misplaced padding and length mod 4 == 1.
        if text.contains("=") {
            guard text.utf8.count.isMultiple(of: 4) else { throw HarborPluginGRPCError.invalidBase64 }
        } else {
            let remainder = text.utf8.count % 4
            guard remainder != 1 else { throw HarborPluginGRPCError.invalidBase64 }
            if remainder != 0 { text += String(repeating: "=", count: 4 - remainder) }
        }
        guard let payload = Data(base64Encoded: text) else { throw HarborPluginGRPCError.invalidBase64 }
        guard payload.count <= maximumBytes else { throw HarborPluginGRPCError.tooLarge }
        let count = UInt32(payload.count)
        var frame = Data([0, UInt8((count >> 24) & 255), UInt8((count >> 16) & 255), UInt8((count >> 8) & 255), UInt8(count & 255)])
        frame.append(payload); return frame
    }

    static func timeoutMilliseconds(_ value: Double?) -> Double {
        let timeout = value == nil || value == 0 || value?.isNaN == true ? 20_000 : value!
        return min(max(timeout, 1_000), 45_000)
    }

    static func response(status: Int, headers: [String: String], bytes: Data) throws -> JSONValue {
        // Desktop caps the complete response before parsing. A cut frame is still an error.
        let data = Array(bytes.prefix(maximumBytes))
        var messages: [String] = []
        var trailers: [String: String] = [:]
        var offset = 0
        while offset < data.count {
            guard data.count - offset >= 5 else { throw HarborPluginGRPCError.incompleteHeader }
            let flags = data[offset]
            let size = data[(offset + 1)..<(offset + 5)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            offset += 5
            guard UInt64(size) <= UInt64(data.count - offset) else { throw HarborPluginGRPCError.incompletePayload }
            let payload = Data(data[offset..<(offset + Int(size))]); offset += Int(size)
            if flags & 0x80 != 0 {
                guard flags == 0x80 else { throw HarborPluginGRPCError.trailerFlags }
                var text = String(decoding: payload, as: UTF8.self)
                if text.hasPrefix("\u{feff}") { text.removeFirst() }
                for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                    guard let colon = line.firstIndex(of: ":"), colon != line.startIndex else { continue }
                    let key = String(line[..<colon]).trimmingCharacters(in: whitespace).lowercased()
                    let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: whitespace)
                    trailers[key] = value
                }
            } else {
                guard flags <= 1 else { throw HarborPluginGRPCError.messageFlags }
                guard flags & 1 == 0 else { throw HarborPluginGRPCError.compressed }
                messages.append(payload.base64EncodedString())
            }
        }
        let rawStatus = trailers["grpc-status"] ?? headers["grpc-status"]
        let grpcStatus = rawStatus.map(javascriptNumber)
        let encodedMessage = trailers["grpc-message"] ?? headers["grpc-message"]
        let message = encodedMessage.flatMap { $0.removingPercentEncoding ?? $0 }
        let successfulRPC = grpcStatus.map { $0 == 0 } ?? !messages.isEmpty
        var result: [String: JSONValue] = [
            "status": .integer(Int64(status)), "ok": .bool((200..<300).contains(status) && successfulRPC),
            "headers": .object(headers.mapValues(JSONValue.string)), "body": .string(messages.first ?? ""),
            "messages": .array(messages.map(JSONValue.string)), "trailers": .object(trailers.mapValues(JSONValue.string))
        ]
        if let grpcStatus, grpcStatus.isFinite { result["grpcStatus"] = .number(grpcStatus) }
        if let message { result["grpcMessage"] = .string(message) }
        return .object(result)
    }

    private static func javascriptNumber(_ raw: String) -> Double {
        let text = raw.trimmingCharacters(in: whitespace)
        if text.isEmpty { return 0 }
        if text == "Infinity" || text == "+Infinity" { return .infinity }
        if text == "-Infinity" { return -.infinity }
        let lower = text.lowercased()
        for (prefix, radix) in [("0x", 16), ("0b", 2), ("0o", 8)] where lower.hasPrefix(prefix) {
            let digits = text.dropFirst(2)
            guard !digits.isEmpty else { return .nan }
            var number: Double = 0
            for scalar in digits.unicodeScalars {
                let digit: UInt32
                switch scalar.value {
                case 48...57: digit = scalar.value - 48
                case 65...70: digit = scalar.value - 65 + 10
                case 97...102: digit = scalar.value - 97 + 10
                default: return .nan
                }
                guard digit < UInt32(radix) else { return .nan }
                number = number * Double(radix) + Double(digit)
            }
            return number
        }
        // Double accepts spellings (inf/nan) that JavaScript Number does not.
        guard text.range(of: "^[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?$", options: .regularExpression) != nil else { return .nan }
        return Double(text) ?? .nan
    }
}
