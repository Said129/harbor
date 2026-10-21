import SwiftUI

private struct ReadingPluginEnvironmentKey: EnvironmentKey {
    static let defaultValue: HarborReadingPluginManager? = nil
}
extension EnvironmentValues {
    var readingPlugins: HarborReadingPluginManager? {
        get { self[ReadingPluginEnvironmentKey.self] }
        set { self[ReadingPluginEnvironmentKey.self] = newValue }
    }
}
