import SwiftUI
import UIKit

/// Shared by profile unlock, PIN confirmation and parental exit. Completion must
/// call the store's real verification/save API; the view never grants an unlock.
@MainActor struct ProfilePINEntryView: View {
    enum Mode: Equatable, Sendable { case set, verify }
    let requestID: String
    let title: String
    let subtitle: String
    let mode: Mode
    let failureMessage: String
    let complete: @MainActor (String) async throws -> Bool
    let back: @MainActor () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @FocusState private var keyboardFocused: Bool
    @State private var pin = ""
    @State private var first = ""
    @State private var confirming = false
    @State private var busy = false
    @State private var error: String?
    @State private var inputRevision = 0
    @State private var shake = 0
    @State private var appearance = UUID()
    @State private var visible = false

    var body: some View {
        keyboardInput
            .accessibilityIdentifier("profile-pin-screen")
            .task(id: inputRevision) { await submitIfComplete() }
            .onAppear { visible = true; reset(); keyboardFocused = true }
            .onChange(of: requestID) { _, _ in reset(); keyboardFocused = true }
            .onDisappear { visible = false; reset(); keyboardFocused = false }
    }
    private var content: some View {
        VStack(spacing: 28) {
            HStack {
                Button { cancel() } label: {
                    Label(DesktopInterfaceText.value("common.back"), systemImage: "chevron.backward")
                        .font(HarborTheme.font(12.5, weight: .medium)).frame(minHeight: 44).padding(.horizontal, 8)
                }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityIdentifier("profile-pin-back")
                Spacer()
            }
            heading
            VStack(spacing: 20) {
                indicators
                if let error {
                    Text(error).font(HarborTheme.font(12.5, weight: .medium)).foregroundStyle(Color(red: 252.0 / 255, green: 165.0 / 255, blue: 165.0 / 255))
                        .multilineTextAlignment(.center).accessibilityIdentifier("profile-pin-error")
                }
                keypad
                if busy { HarborLoader().frame(width: 24, height: 24).accessibilityIdentifier("profile-pin-busy") }
            }.modifier(ProfilePINShake(progress: reduceMotion ? 0 : Double(shake)))
                .animation(reduceMotion ? nil : .linear(duration: 0.34), value: shake)
            Text(DesktopInterfaceText.value("Type on your keyboard or tap the digits above."))
                .font(HarborTheme.font(11.5)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: 420).foregroundStyle(HarborTheme.ink)
    }
    private var keyboardInput: some View {
        content
            .focusable(true, interactions: .edit).focused($keyboardFocused)
            .onKeyPress(characters: CharacterSet(charactersIn: "0123456789"), phases: .down) { press in
                guard !busy else { return .handled }
                for digit in press.characters { append(String(digit)) }; return .handled
            }
            .onKeyPress(.delete) { erase(); return .handled }
            .onKeyPress(.escape) { cancel(); return .handled }
            .opacity(visible || reduceMotion ? 1 : 0).offset(y: visible || reduceMotion ? 0 : 8)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: visible)
    }
    private var heading: some View {
        VStack(spacing: 8) {
            Text(DesktopInterfaceText.value("Profile PIN").uppercased()).font(HarborTheme.font(11, weight: .bold)).tracking(layoutDirection == .rightToLeft ? 0 : 3.5).foregroundStyle(.secondary)
            Text(confirming ? DesktopInterfaceText.value("Confirm your PIN") : title)
                .font(HarborTheme.displayFont(28)).multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
            Text(confirming ? DesktopInterfaceText.value("Type the same 4-digit PIN again.") : subtitle)
                .font(HarborTheme.font(13.5)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }
    private var indicators: some View {
        Button { keyboardFocused = true } label: {
            HStack(spacing: 12) {
                ForEach(0..<4) { index in
                    Circle().fill(pin.count > index ? HarborTheme.ink : .clear).frame(width: 14, height: 14)
                        .overlay { Circle().stroke(HarborTheme.ink.opacity(pin.count > index ? 1 : 0.18), lineWidth: 1) }
                        .scaleEffect(pin.count > index && !reduceMotion ? 1.1 : 1)
                }
            }.padding(.horizontal, 12).frame(minHeight: 44).contentShape(Rectangle())
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: pin.count)
        }.buttonStyle(.plain).disabled(busy).privacySensitive()
            .accessibilityLabel(DesktopInterfaceText.value("PIN")).accessibilityValue("\(pin.count) / 4")
            .accessibilityIdentifier("profile-pin-entry").environment(\.layoutDirection, .leftToRight)
    }
    private var keypad: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(48), spacing: 10), count: 3), spacing: 10) {
            ForEach(1...9, id: \.self) { value in digit(String(value)) }
            Color.clear.frame(width: 48, height: 48).accessibilityHidden(true)
            digit("0")
            Button { erase() } label: { Image(systemName: "delete.left").font(.system(size: 18)).frame(width: 48, height: 48) }
                .buttonStyle(ProfilePINKeyStyle()).disabled(busy || pin.isEmpty)
                .accessibilityLabel(DesktopInterfaceText.value("Delete")).accessibilityIdentifier("profile-pin-delete")
        }.frame(width: 164).environment(\.layoutDirection, .leftToRight)
    }
    private func digit(_ value: String) -> some View {
        Button { append(value) } label: { Text(value).font(HarborTheme.font(20, weight: .medium)).monospacedDigit().frame(width: 48, height: 48) }
            .buttonStyle(ProfilePINKeyStyle()).disabled(busy).accessibilityIdentifier("profile-pin-digit-" + value)
    }
    private func append(_ digit: String) {
        guard !busy, pin.count < 4, digit.utf8.count == 1, let value = digit.utf8.first, (48...57).contains(value) else { return }
        error = nil; pin += digit; inputRevision += 1; keyboardFocused = true
    }
    private func erase() { guard !busy, !pin.isEmpty else { return }; error = nil; pin.removeLast(); inputRevision += 1; keyboardFocused = true }
    private func reset() { appearance = UUID(); pin = ""; first = ""; confirming = false; busy = false; error = nil; inputRevision += 1 }
    private func cancel() { reset(); back() }
    private func reject(_ message: String) {
        pin = ""; inputRevision += 1; error = message; shake += 1; keyboardFocused = true
        UIAccessibility.post(notification: .announcement, argument: message)
    }
    private func submitIfComplete() async {
        guard visible, !busy, pin.count == 4 else { return }
        if mode == .set && !confirming { first = pin; pin = ""; confirming = true; inputRevision += 1; return }
        if mode == .set && pin != first {
            first = ""; confirming = false; reject(DesktopInterfaceText.value("PINs didn't match. Start over.")); return
        }
        let expectedAppearance = appearance, expectedRequest = requestID, suppliedPIN = pin
        busy = true
        defer { if appearance == expectedAppearance { busy = false } }
        do {
            let accepted = try await complete(suppliedPIN)
            try Task.checkCancellation()
            guard visible, appearance == expectedAppearance, requestID == expectedRequest else { return }
            if accepted { pin = ""; first = ""; confirming = false; inputRevision += 1 }
            else { reject(mode == .verify ? DesktopInterfaceText.value("Wrong PIN") : failureMessage) }
        } catch is CancellationError { return }
        catch {
            guard visible, appearance == expectedAppearance, requestID == expectedRequest else { return }
            reject(failureMessage)
        }
    }
}

private struct ProfilePINKeyStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(HarborTheme.background.opacity(configuration.isPressed ? 0.8 : 0.55), in: .circle)
            .overlay { Circle().stroke(HarborTheme.ink.opacity(0.12), lineWidth: 1) }
            .contentShape(Circle()).opacity(enabled ? 1 : 0.4).scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
private struct ProfilePINShake: GeometryEffect {
    var progress: Double
    var animatableData: Double { get { progress } set { progress = newValue } }
    func effectValue(size: CGSize) -> ProjectionTransform {
        let positions = [0.0, -8, 8, -5, 5, 0]
        let phase = (progress - floor(progress)) * 5
        let index = min(4, Int(phase)), fraction = phase - Double(index)
        return ProjectionTransform(CGAffineTransform(translationX: positions[index] + (positions[index + 1] - positions[index]) * fraction, y: 0))
    }
}
