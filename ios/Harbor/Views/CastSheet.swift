import SwiftUI

/// Desktop's cast menu (`cast-menu.tsx`) and cast session bar (`cast-session-bar.tsx`) for Roku and DLNA renderers.
/// Chromecast and AirPlay are not here; AirPlay already has its own route picker in the player.
struct CastSheet: View {
    let controller: CastController
    let mediaURL: String
    let title: String
    let startSeconds: Double
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""

    var body: some View {
        NavigationStack {
            List {
                if controller.selected != nil {
                    CastSessionSection(controller: controller)
                }
                CastTargetsSection(controller: controller, mediaURL: mediaURL, title: title, startSeconds: startSeconds)
                CastAddressSection(controller: controller, address: $address)
                if let failure = controller.failure {
                    CastFailureSection(failure: failure)
                }
            }
            .navigationTitle(DesktopInterfaceText.value("Cast to TV or speaker"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(DesktopInterfaceText.value("Close")) { dismiss() }
                }
            }
            .task {
                if controller.targets.isEmpty { await controller.scan() }
            }
        }
        .tint(HarborTheme.accent)
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
    }
}

private struct CastTargetsSection: View {
    let controller: CastController
    let mediaURL: String
    let title: String
    let startSeconds: Double

    var body: some View {
        Section {
            if controller.scanning {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(DesktopInterfaceText.value("Scanning your network…"))
                }
            } else if controller.targets.isEmpty {
                Text(DesktopInterfaceText.value("No Chromecast, DLNA, or Roku devices found. Make sure your TV is on, woken up, and on the same Wi-Fi."))
                    .foregroundStyle(.secondary)
            }
            ForEach(controller.targets) { target in
                Button {
                    Task { await controller.cast(to: target, mediaURL: mediaURL, contentType: nil, title: title, startSeconds: startSeconds) }
                } label: {
                    CastTargetRow(target: target)
                }
                .accessibilityIdentifier("cast-target-" + target.kind.rawValue)
            }
            Button(DesktopInterfaceText.value(controller.targets.isEmpty ? "Scan again" : "Rescan")) {
                Task { await controller.scan() }
            }
            .disabled(controller.scanning)
        }
    }
}

private struct CastTargetRow: View {
    let target: CastTarget

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: target.kind == .roku ? "tv" : "speaker.wave.2")
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(target.name)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var detail: String {
        if let model = target.model, !model.isEmpty { return model }
        if target.kind == .dlna { return DesktopInterfaceText.value("DLNA TV") }
        return target.host
    }
}

/// Manual entry: a Roku address on port 8060, or a DLNA device-description URL. iOS has no multicast discovery.
private struct CastAddressSection: View {
    let controller: CastController
    @Binding var address: String

    var body: some View {
        Section {
            TextField(DesktopInterfaceText.value("Host or address"), text: $address)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .accessibilityIdentifier("cast-address-field")
            Button(DesktopInterfaceText.value("Add")) {
                let value = address
                address = ""
                Task { await controller.addManual(value) }
            }
            .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

private struct CastSessionSection: View {
    let controller: CastController
    @State private var seekDraft: Double = 0
    @State private var editingSeek = false

    var body: some View {
        Section {
            if let target = controller.selected {
                Text(sessionLabel(target)).font(.headline)
                transportRow
                if target.kind == .dlna {
                    seekRow
                    volumeRow
                }
            }
        }
        .onChange(of: controller.positionSec) { _, value in
            if !editingSeek { seekDraft = value }
        }
    }

    private func sessionLabel(_ target: CastTarget) -> String {
        let prefix: String
        switch controller.phase {
        case .connecting: prefix = "Connecting to"
        case .paused: prefix = "Paused on"
        case .playing, .idle: prefix = "Casting to"
        }
        return DesktopInterfaceText.value(prefix) + " " + target.name
    }

    private var transportRow: some View {
        HStack(spacing: 18) {
            Button {
                Task { await controller.togglePlayback() }
            } label: {
                Image(systemName: controller.phase == .playing ? "pause.fill" : "play.fill")
            }
            .accessibilityLabel(DesktopInterfaceText.value(controller.phase == .playing ? "Pause" : "Play"))
            Text(CastNet.formatHMS(controller.positionSec))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button(DesktopInterfaceText.value("Stop"), role: .destructive) {
                Task { await controller.stop() }
            }
            .accessibilityIdentifier("cast-stop")
        }
    }

    private var seekRow: some View {
        Slider(
            value: $seekDraft,
            in: 0...max(controller.durationSec ?? controller.positionSec, 1),
            onEditingChanged: { editing in
                editingSeek = editing
                if !editing {
                    Task { await controller.seek(to: seekDraft) }
                }
            }
        )
    }

    private var volumeRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(DesktopInterfaceText.value("Volume")).font(.caption).foregroundStyle(.secondary)
            Slider(
                value: Binding(get: { controller.volume }, set: { controller.volume = $0 }),
                in: 0...100,
                onEditingChanged: { editing in
                    if !editing {
                        Task { await controller.setVolume(controller.volume) }
                    }
                }
            )
            Text(DesktopInterfaceText.value("Adjust volume on the speaker. Computer volume and boost do not apply."))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct CastFailureSection: View {
    let failure: CastController.Failure

    var body: some View {
        Section {
            if !failure.title.isEmpty {
                Text(failure.title).font(.headline)
            }
            Text(failure.message)
            ForEach(Array(failure.steps.enumerated()), id: \.offset) { index, step in
                Text("\(index + 1). " + step).font(.footnote)
            }
        }
    }
}
