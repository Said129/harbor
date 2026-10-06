import Foundation
import Observation

@MainActor @Observable
final class StreamPreferences {
    static let shared = StreamPreferences()
    var automatic = UserDefaults.standard.object(forKey: "streams.automatic") as? Bool ?? true {
        didSet { UserDefaults.standard.set(automatic, forKey: "streams.automatic") }
    }
    var excludeCamera = UserDefaults.standard.object(forKey: "streams.excludeCamera") as? Bool ?? true {
        didSet { UserDefaults.standard.set(excludeCamera, forKey: "streams.excludeCamera") }
    }
    var maximum = UserDefaults.standard.object(forKey: "streams.maximum") as? Int ?? 2160 {
        didSet { UserDefaults.standard.set(maximum, forKey: "streams.maximum") }
    }
    var minimum = UserDefaults.standard.object(forKey: "streams.minimum") as? Int ?? 0 {
        didSet { UserDefaults.standard.set(minimum, forKey: "streams.minimum") }
    }
    func filter(_ offers: [StreamOffer]) -> [StreamOffer] {
        offers.filter { offer in
            if excludeCamera && offer.cameraRecording { return false }
            let height = offer.videoHeight
            return height <= maximum && (minimum == 0 || height >= minimum)
        }
    }
    func preferred(_ offers: [StreamOffer]) -> StreamOffer? {
        let candidates = offers.filter(\.automaticallyPlayable)
        // Rust ranking still breaks ties within the same resolution.
        let bestHeight = candidates.map(\.videoHeight).max()
        return candidates.first { $0.videoHeight == bestHeight }
    }
}

extension StreamOffer {
    var automaticallyPlayable: Bool {
        guard let value = raw["url"].string, value.rangeOfCharacter(from: .controlCharacters) == nil,
              let url = URLComponents(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty else { return false }
        return true
    }
    var videoHeight: Int {
        if quality.hasPrefix("4K") { return 2160 }
        if quality.hasPrefix("1080p") { return 1080 }
        if quality == "720p" { return 720 }
        return 0
    }
    var cameraRecording: Bool {
        if quality == "ROUGH" { return true }
        let source = raw["source"].string?.lowercased() ?? ""
        if ["cam", "ts", "hdts", "tc", "telesync", "telecine", "workprint"].contains(source) { return true }
        let text = [raw["name"].string, raw["title"].string, raw["description"].string].compactMap { $0 }.joined(separator: " ")
        return text.range(of: "(?i)(?:^|[^a-z0-9])(?:hdcam|camrip|cam|hdts|telesync|telecine|tsrip|ts|tc)(?:$|[^a-z0-9])", options: .regularExpression) != nil
    }
}
