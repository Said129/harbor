import AVKit
import SwiftUI

/// AVKit owns discovery, selection and accessibility; Harbor supplies its glyph.
@MainActor
struct AudioRoutePicker: View {
    let state: PlayerState

    var body: some View {
        ZStack {
            Image("player-cast").resizable().scaledToFit().frame(width: 22, height: 22)
                .foregroundStyle(state.wirelessAudio ? HarborTheme.accent : .white)
                .accessibilityHidden(true).allowsHitTesting(false)
            NativeAudioRoutePicker(state: state)
        }.frame(width: 44, height: 44)
    }
}

@MainActor
private struct NativeAudioRoutePicker: UIViewRepresentable {
    let state: PlayerState

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView(frame: .zero)
        picker.delegate = context.coordinator
        picker.prioritizesVideoDevices = false
        picker.tintColor = .clear
        picker.activeTintColor = .clear
        picker.backgroundColor = .clear
        picker.accessibilityLabel = "AirPlay · Audio"
        picker.accessibilityIdentifier = "player-audio-output"
        return picker
    }
    func updateUIView(_ picker: AVRoutePickerView, context: Context) {
        picker.accessibilityValue = state.audioOutput
    }
    static func dismantleUIView(_ picker: AVRoutePickerView, coordinator: Coordinator) {
        picker.delegate = nil
        coordinator.state.choosingAudioRoute = false
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency AVRoutePickerViewDelegate {
        let state: PlayerState
        init(state: PlayerState) { self.state = state }
        func routePickerViewWillBeginPresentingRoutes(_ routePickerView: AVRoutePickerView) {
            state.choosingAudioRoute = true
        }
        func routePickerViewDidEndPresentingRoutes(_ routePickerView: AVRoutePickerView) {
            state.choosingAudioRoute = false
        }
    }
}
