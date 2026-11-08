import SwiftUI

enum SubtitleSyncPhase: String, Sendable {
    case idle, analyzing, applying, offered, synced, declined, failed
    var working: Bool { self == .analyzing || self == .applying }
    var title: String {
        switch self {
        case .idle: "Auto-sync"
        case .analyzing, .applying: "Syncing subtitles…"
        case .offered: "Subtitles may be off"
        case .synced: "Subtitles synced"
        case .declined, .failed: "Couldn't auto-sync"
        }
    }
}

struct SubtitleSyncFeedback: View {
    let state: PlayerState
    @State private var visible = false
    var body: some View {
        VStack {
            if visible && state.subtitleSyncPhase != .idle {
                HStack(spacing: 8) {
                    if state.subtitleSyncPhase.working { ProgressView().tint(.white) }
                    else { Image(systemName: state.subtitleSyncPhase == .synced ? "checkmark.circle.fill" : "info.circle") }
                    Text(DesktopInterfaceText.value(state.subtitleSyncPhase.title))
                        .font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    if state.subtitleSyncPhase == .offered {
                        Button(DesktopInterfaceText.value("Sync")) { state.controller?.applySubtitleSyncOffer() }
                            .buttonStyle(.borderedProminent).frame(minHeight: 44)
                            .accessibilityIdentifier("subtitle-sync-apply-offer")
                        Button { state.controller?.cancelSubtitleSync() } label: {
                            Image(systemName: "xmark").frame(minWidth: 44, minHeight: 44)
                        }.accessibilityLabel(DesktopInterfaceText.value("Dismiss"))
                    }
                }.foregroundStyle(.white).padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: .capsule)
                    .accessibilityElement(children: state.subtitleSyncPhase == .offered ? .contain : .combine)
                    .accessibilityValue(state.subtitleSyncMessage.map { DesktopInterfaceText.value($0) } ?? "")
                    .accessibilityIdentifier("subtitle-sync-feedback")
            }
            Spacer()
        }.padding(.top, 16).padding(.horizontal, 16)
            .allowsHitTesting(visible && state.subtitleSyncPhase == .offered)
            .task(id: state.subtitleSyncRevision) {
                visible = state.subtitleSyncPhase != .idle
                guard visible, !state.subtitleSyncPhase.working else { return }
                if UIAccessibility.isVoiceOverRunning {
                    UIAccessibility.post(notification: .announcement, argument: DesktopInterfaceText.value(state.subtitleSyncPhase.title))
                }
                guard state.subtitleSyncPhase != .offered else { return }
                do { try await Task.sleep(for: .seconds(6)); visible = false } catch {}
            }
    }
}
