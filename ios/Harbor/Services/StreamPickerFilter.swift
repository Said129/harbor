import Foundation

enum StreamPickerFilter {
    static func sources(_ offers: [StreamOffer], quality: String?, provider: String?) -> [StreamOffer] {
        offers.filter { (quality == nil || $0.pickerQualityGroup == quality) && (provider == nil || $0.pickerInstance == provider) }
    }
}

extension StreamOffer {
    var pickerQualityGroup: String {
        if quality.hasPrefix("4K") { return "4K" }
        if quality.hasPrefix("1080p") { return "1080p" }
        return quality.isEmpty ? "SD" : quality
    }
}
