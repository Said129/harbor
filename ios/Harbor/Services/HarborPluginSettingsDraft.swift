import Foundation
import Observation

@MainActor @Observable final class HarborPluginSettingsDraft {
    private let manager: HarborStreamPluginManager
    let plugin: HarborInstalledStreamPlugin
    private var generation = UUID()
    private(set) var fields: [HarborPluginSettingsField] = []
    var values: [String: JSONValue] = [:]
    private(set) var ready = false
    private(set) var saving = false
    private(set) var failure: String?

    init(manager: HarborStreamPluginManager, plugin: HarborInstalledStreamPlugin) { self.manager = manager; self.plugin = plugin }

    func load() async {
        let ticket = generation; ready = false; failure = nil
        do {
            let fields = try await manager.settingsFields(plugin.id)
            var values = try await manager.configuration(plugin.id)
            try Task.checkCancellation()
            guard ticket == generation, manager.document.plugins.first(where: { $0.id == plugin.id }) == plugin else { throw HarborPluginRepositoryError("plugin-candidate-changed") }
            for field in fields {
                guard let key = field.key, values[key] == nil else { continue }
                switch field.type {
                case "toggle": values[key] = .bool(field.defaultValue == .bool(true))
                case "select": values[key] = field.defaultValue ?? .string(field.options?.first?.value ?? "")
                case "text": values[key] = field.defaultValue ?? .string("")
                default: break
                }
            }
            self.fields = fields; self.values = values; ready = true
        } catch {
            guard ticket == generation, !Task.isCancelled else { return }
            failure = HarborPluginMessages.error(error)
        }
    }
    func save() async -> Bool {
        guard ready, !saving else { return false }
        let ticket = generation; saving = true; failure = nil
        defer { if ticket == generation { saving = false } }
        do {
            let declared = Set(fields.compactMap(\.key))
            let passwords = Set(fields.filter { $0.isPassword == true }.compactMap(\.key))
                .union(Set(plugin.secretKeys).subtracting(declared))
            try await manager.saveSettings(plugin.id, values: values, passwordKeys: passwords, expected: plugin)
            try Task.checkCancellation()
            guard ticket == generation else { return false }
            clear(); return true
        } catch {
            if ticket == generation, !Task.isCancelled { failure = HarborPluginMessages.error(error) }
            return false
        }
    }
    func clear() {
        generation = UUID(); fields = []; values = [:]; ready = false; saving = false; failure = nil
    }
}

enum HarborPluginMessages {
    static func error(_ error: Error) -> String {
        let code = (error as? HarborPluginRepositoryError)?.code ?? (error as? HarborError)?.code ?? "plugin-operation"
        let label: String
        switch code {
        case "only-https": label = "Only https links are accepted."
        case "already-added": label = "Already added."
        case "no-answer", "fetch-failed", "plugin-network-request": label = "That link did not answer."
        case "stremio-addon": label = "This is a Stremio addon manifest. Add it from the Addons page instead."
        case "manga-repo": label = "This is a manga repository. Add it from the Manga page."
        case "android-extensions": label = "This kind of extension can only be installed in the desktop app."
        case "too-large": label = "File is larger than 2 MB."
        case "checksum": label = "Checksum did not match the manifest."
        case "not-stream-plugin": label = "Not a stream plugin: it exports no getStreams or streams function."
        case "plugin-candidate-changed", "plugin-scope", "plugin-not-installed": label = "Settings changed. Please reopen this page."
        default: label = "Could not complete this action. Try again."
        }
        return DesktopInterfaceText.value(label)
    }
}
