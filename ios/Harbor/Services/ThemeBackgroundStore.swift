import Foundation
import UIKit

/// Stores theme background images as JPEG files in Application Support.
/// The active background is `activeName`; saved library themes keep their own copy.
struct ThemeBackgroundStore {
    static let shared = ThemeBackgroundStore()
    static let activeName = "active.jpg"
    /// Stored images stay under the 1.2 MB share budget Desktop uses for exported backgrounds.
    static let maxStoredBytes = 900_000
    static let maxDimension: CGFloat = 2560

    private let root: URL

    init(root: URL? = nil) {
        self.root = root ?? URL.applicationSupportDirectory.appendingPathComponent("HarborThemeBackgrounds", isDirectory: true)
    }

    static func name(for entryID: String) -> String {
        entryID + ".jpg"
    }

    func read(_ name: String) -> Data? {
        try? Data(contentsOf: root.appendingPathComponent(name))
    }

    func write(_ data: Data, name: String) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: root.appendingPathComponent(name), options: .atomic)
    }

    func remove(_ name: String) {
        try? FileManager.default.removeItem(at: root.appendingPathComponent(name))
    }

    /// Writes a theme file to the temporary folder so it can be shared.
    func exportFile(_ data: Data, fileName: String) -> URL? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("HarborThemeExport", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(fileName)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Downscales to at most `maxDimension` and re-encodes as JPEG under `maxStoredBytes`.
    static func normalizedJPEG(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let width = image.size.width
        let height = image.size.height
        guard width > 0, height > 0 else { return nil }
        let scale = min(1, maxDimension / max(width, height))
        let size = CGSize(width: max(1, (width * scale).rounded()), height: max(1, (height * scale).rounded()))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        for quality in [0.85, 0.7, 0.55, 0.4] as [CGFloat] {
            if let jpeg = resized.jpegData(compressionQuality: quality), jpeg.count <= maxStoredBytes {
                return jpeg
            }
        }
        return nil
    }
}
