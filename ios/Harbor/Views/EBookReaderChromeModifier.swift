import SwiftUI

struct EBookImmersiveChromePreference: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

struct EBookReaderChromeModifier: ViewModifier {
    let chrome: EBookReaderChrome
    let focus: Bool
    let suspended: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle()).simultaneousGesture(TapGesture().onEnded { reveal() }, including: focus && !suspended ? .all : .subviews)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: chrome.visible)
            .toolbar(chrome.visible ? .visible : .hidden, for: .navigationBar)
            .statusBarHidden(!chrome.visible)
            .preference(key: EBookImmersiveChromePreference.self, value: !chrome.visible)
            .onAppear { reveal() }
            .onChange(of: focus) { _, _ in reveal() }
            .onChange(of: suspended) { _, _ in reveal() }
            .onDisappear { chrome.stop() }
    }
    private func reveal() { chrome.reveal(focus: focus, suspended: suspended) }
}
