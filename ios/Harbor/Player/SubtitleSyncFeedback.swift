import SwiftUI

enum SubtitleSyncPhase: String, Sendable {
    case idle, analyzing, applying, synced, declined, failed
    var working: Bool { self == .analyzing || self == .applying }
    var title: String {
        switch self {
        case .idle: "Auto-sync"
        case .analyzing, .applying: "Syncing subtitles…"
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
                }.foregroundStyle(.white).padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: .capsule)
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(state.subtitleSyncMessage.map { DesktopInterfaceText.value($0) } ?? "")
                    .accessibilityIdentifier("subtitle-sync-feedback")
            }
            Spacer()
        }.padding(.top, 16).padding(.horizontal, 56).allowsHitTesting(false)
            .task(id: state.subtitleSyncRevision) {
                visible = state.subtitleSyncPhase != .idle
                guard visible, !state.subtitleSyncPhase.working else { return }
                if UIAccessibility.isVoiceOverRunning {
                    UIAccessibility.post(notification: .announcement, argument: DesktopInterfaceText.value(state.subtitleSyncPhase.title))
                }
                do { try await Task.sleep(for: .seconds(6)); visible = false } catch {}
            }
    }
}
