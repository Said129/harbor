import Foundation

struct ProfileLaunchPreferences: Equatable, Sendable {
    enum Interval: String, CaseIterable, Sendable {
        case launch, fifteenMinutes = "15m", thirtyMinutes = "30m", never
        var title: String {
            switch self {
            case .launch: "Every launch"
            case .fifteenMinutes: "Every 15 min"
            case .thirtyMinutes: "Every 30 min"
            case .never: "Never"
            }
        }
        var seconds: TimeInterval? {
            switch self { case .fifteenMinutes: 900; case .thirtyMinutes: 1_800; default: nil }
        }
    }
    enum Action: Equatable, Sendable { case resume, choose, useDefault(String) }
    var interval: Interval = .launch
    var defaultID = ""
    var valid: Bool { defaultID.utf8.count <= 256 && defaultID.rangeOfCharacter(from: .controlCharacters) == nil }
    func defaultProfile(in profiles: [DeviceHouseholdProfile]) -> DeviceHouseholdProfile? {
        profiles.first { $0.id == defaultID && !$0.desktop.isKid && $0.credential == nil }
    }
    func promptOnReturn(profiles: [DeviceHouseholdProfile], lastSelected: TimeInterval, now: TimeInterval) -> Bool {
        guard profiles.filter({ !$0.desktop.isKid }).count > 1, let seconds = interval.seconds,
              now.isFinite, now >= 0 else { return false }
        let previous = lastSelected.isFinite && lastSelected >= 0 ? lastSelected : 0
        return now - previous >= seconds
    }
    func launchAction(profiles: [DeviceHouseholdProfile], selectedID: String?, selectedUnlocked: Bool, lastSelected: TimeInterval, now: TimeInterval) -> Action {
        if let profile = defaultProfile(in: profiles) { return .useDefault(profile.id) }
        guard selectedUnlocked, profiles.contains(where: { $0.id == selectedID && !$0.desktop.isKid }) else { return .choose }
        guard profiles.filter({ !$0.desktop.isKid }).count > 1 else { return .resume }
        if interval == .launch || promptOnReturn(profiles: profiles, lastSelected: lastSelected, now: now) { return .choose }
        return .resume
    }
}

/// Selection timing is local to this device/household, never a synchronized PIN
/// exemption. Automatic defaults and closing the picker do not update this clock.
@MainActor final class ProfileSelectionClock {
    private let storage: UserDefaults
    private let key: String
    init(scope: HouseholdProfileScope, storage: UserDefaults = .standard) {
        self.storage = storage; key = "harbor.profile.lastSelectAt." + scope.key
    }
    var lastSelected: TimeInterval {
        let value = storage.double(forKey: key)
        return value.isFinite && value >= 0 ? value : 0
    }
    func recordSelection(at now: TimeInterval = Date().timeIntervalSince1970) {
        guard now.isFinite, now >= 0 else { return }; storage.set(now, forKey: key)
    }
}
