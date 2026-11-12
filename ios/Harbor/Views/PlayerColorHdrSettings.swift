import SwiftUI

/// Desktop's "Color & HDR" section: the tone-mapping curve. Boosting standard video toward HDR (`inverse-tone-mapping`)
/// is not offered, because the iPhone renderer draws to an 8-bit standard-range surface that has no HDR range to expand into.
/// The value is read when a video opens (`MPVConfiguration`), like the HDR-to-SDR switch above it.
struct PlayerColorHdrSettings: View {
    @AppStorage(PlayerToneMapping.curveKey) private var storedCurve = ""

    private var selection: Binding<String> {
        Binding<String>(get: { PlayerToneMapping.curve(storedCurve).rawValue }, set: { storedCurve = $0 })
    }

    private var choices: [(String, String)] {
        ToneMappingCurve.allCases.map { ($0.title, $0.rawValue) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HarborSettingsChoice("Tone-mapping curve", selection: selection, choices: choices, identifier: "settings-tone-mapping")
            Text(DesktopInterfaceText.value("Controls how bright highlights are reduced to fit your display. Changes apply to the next video you play."))
                .font(HarborTheme.font(12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
