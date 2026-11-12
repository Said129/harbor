import SwiftUI
import UIKit

enum PlayerSettingsPage: String, Identifiable {
    case options, playback, video, audio, subtitles
    var id: String { rawValue }
    var title: String { DesktopInterfaceText.value(sourceTitle) }
    private var sourceTitle: String {
        switch self {
        case .options: "Opciones del reproductor"
        case .playback: "Reproducción"
        case .video: "Vídeo"
        case .audio: "Audio"
        case .subtitles: "Subtítulos"
        }
    }
    var icon: String {
        switch self {
        case .options: "nav-settings"
        case .playback: "ui-play-filled"
        case .video: "desktop-image"
        case .audio: "player-audio"
        case .subtitles: "ui-customize-subtitles"
        }
    }
}

struct PlayerSettingsView: View {
    let page: PlayerSettingsPage
    var state: PlayerState? = nil
    var changeSource: (() -> Void)? = nil
    /// The playing session, which the Options page needs to offer saving the video that is playing.
    var session: PlaybackSession? = nil
    var media: Media? = nil
    @Bindable var preferences = PlaybackPreferences.shared
    @Bindable private var sources = StreamPreferences.shared
    @Bindable private var advisory = ContentAdvisoryPreferences.shared
    @AppStorage("mpvHwdec") private var hardwareDecoding = HardwareDecoding.auto
    /// Desktop's `mpvQuality` profile, read by `MPVConfiguration` when a video opens.
    @AppStorage(UISettingsPolicy.mpvQualityKey) private var mpvQuality = UISettingsPolicy.mpvQualityDefault
    /// Desktop's `playerHdrToSdr`, read by `MPVConfiguration` when a video opens. iOS starts off, which keeps mpv's own mapping.
    @AppStorage(UISettingsPolicy.hdrToSdrKey) private var playerHdrToSdr = false
    /// Desktop's `mpvBufferBoost`, read by `MPVConfiguration` when a video opens.
    @AppStorage(BufferSize.boostKey) private var mpvBufferBoost = false
    /// Desktop's `mpvQuality` choices, in Desktop's order (`mpv-panel/profile.tsx`).
    private var mpvQualityChoices: [(String, String)] {
        [(DesktopInterfaceText.value("Smooth on weak PCs"), "performance"), (DesktopInterfaceText.value("Balanced"), "balanced"),
         (DesktopInterfaceText.value("Maximum quality"), "quality")]
    }
    @AppStorage("resumePlayback") private var resumePlayback = true
    @AppStorage("resumePrompt") private var resumePrompt = false
    @AppStorage("subtitleAutoSync") private var subtitleAutoSync = false
    @AppStorage("autoSyncDrift") private var autoSyncDrift = false
    @AppStorage("subtitleAutoSyncPivot") private var subtitleAutoSyncPivot = false
    @AppStorage("subtitleAutoSyncCrowd") private var subtitleAutoSyncCrowd = true
    @AppStorage("communitySyncOptOut") private var communitySyncOptOut = false
    @AppStorage("communitySyncUrl") private var communitySyncUrl = ""
    @State private var serverEditing = false
    @State private var serverDraft = ""
    @State private var serverInvalid = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                switch page {
                case .options: optionsSettings
                case .playback: playbackSettings
                case .video: videoSettings
                case .audio: audioSettings
                case .subtitles: subtitlesSettings
                }
            }.padding(20)
        }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink)
            .font(HarborTheme.font(14)).buttonStyle(HarborAccountButtonStyle())
            .tint(HarborTheme.accent).accessibilityIdentifier("player-settings-scroll")
            .navigationTitle(page.title).navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var optionsSettings: some View {
        if let changeSource {
            HarborSettingsSection("Fuente") { Button("Cambiar fuente", action: changeSource).accessibilityIdentifier("player-options-change-source") }
        }
        if let session { PlayerDownloadSection(session: session, media: media) }
        HarborSettingsSection("Reproducción") {
            ForEach([PlayerSettingsPage.playback, .video, .audio, .subtitles]) { destination in
                NavigationLink { PlayerSettingsView(page: destination, state: state) } label: {
                    HStack(spacing: 12) {
                        Image(destination.icon).resizable().scaledToFit().frame(width: 20, height: 20).foregroundStyle(.secondary)
                        Text(destination.title).font(HarborTheme.font(15, weight: .semibold))
                        Spacer()
                        Image("desktop-chevron-right").resizable().scaledToFit().frame(width: 16, height: 16).foregroundStyle(.secondary)
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var playbackSettings: some View {
        // The sleep timer belongs to a running video, as in Desktop's speed menu.
        if let state {
            SleepTimerSettings(); ABLoopSettings(state: state)
            HarborSettingsToggle(DesktopInterfaceText.value("Playback stats · press I to hide"), isOn: $preferences.options.showStats)
                .accessibilityIdentifier("settings-playback-stats")
        }
        PlayerPlayModeSettings(automatic: $sources.automatic)
        HarborSettingsSection("Fuentes y calidad") {
            Text("Estos límites de calidad se aplican a la reproducción automática; el filtro de seguridad, el orden de resultados y el diseño del selector están en Ajustes › Fuentes de streaming.").font(HarborTheme.font(12)).foregroundStyle(.secondary)
            HarborSettingsToggle("Ocultar grabaciones de cámara · CAM / TS / TC", isOn: $sources.excludeCamera)
            HarborSettingsChoice("Calidad máxima", selection: $sources.maximum, choices: [("4K", 2160), ("1080p", 1080), ("720p", 720)])
            HarborSettingsChoice("Calidad mínima", selection: $sources.minimum, choices: [("Todas", 0), ("720p", 720), ("1080p", 1080), ("4K", 2160)])
        }
        HarborSettingsSection("Controles") {
            HarborSettingsToggle("Ocultar controles automáticamente", isOn: $preferences.options.autoHideControls)
            HarborSettingsToggle(DesktopInterfaceText.value("Player screen lock"), note: DesktopInterfaceText.value("Show a lock control in the player that blocks mouse, keyboard, remote, and media-key input until you unlock it."), isOn: $preferences.options.screenLock)
                .accessibilityIdentifier("settings-screen-lock")
            HarborSettingsToggle("Mantener la pantalla encendida", isOn: $preferences.options.keepScreenAwake)
            HarborSettingsToggle("Reanudar tras una interrupción de audio", isOn: $preferences.options.resumeAfterInterruption)
            HarborSettingsToggle("Reanudar al volver a la app", isOn: $preferences.options.resumeOnForeground)
            HarborSettingsChoice("Salto al retroceder", selection: $preferences.options.seekBackSeconds, choices: SeekSteps.choices(including: preferences.options.seekBackSeconds).map { ("\(Int($0)) segundos", $0) })
            HarborSettingsChoice("Salto al avanzar", selection: $preferences.options.seekForwardSeconds, choices: SeekSteps.choices(including: preferences.options.seekForwardSeconds).map { ("\(Int($0)) segundos", $0) })
            HarborSettingsChoice(DesktopInterfaceText.value("Short seek (Shift + arrows)") + " ←", selection: $preferences.options.seekBackShortSeconds, choices: SeekSteps.choices(including: preferences.options.seekBackShortSeconds).map { ("\(Int($0)) segundos", $0) },
                                 identifier: "settings-seek-back-short")
            HarborSettingsChoice(DesktopInterfaceText.value("Short seek (Shift + arrows)") + " →", selection: $preferences.options.seekForwardShortSeconds, choices: SeekSteps.choices(including: preferences.options.seekForwardShortSeconds).map { ("\(Int($0)) segundos", $0) },
                                 identifier: "settings-seek-forward-short")
            Text(DesktopInterfaceText.value("A shorter jump on Shift plus the arrow keys, for nudging a few seconds at a time.")).font(HarborTheme.font(12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HarborSettingsToggle(DesktopInterfaceText.value("Ask before leaving"), note: DesktopInterfaceText.value("When Esc would close the player, show a quick confirm first. You can tick \"Don't ask me again\" in that prompt to always leave on Esc."), isOn: $preferences.options.confirmLeave)
                .accessibilityIdentifier("settings-confirm-leave")
            HarborSettingsChoice("Velocidad inicial", selection: $preferences.options.speed, choices: PlaybackSpeeds.choices(current: preferences.options.speed).map { ("\($0.formatted())×", $0) })
            CustomSpeedRow(current: preferences.options.speed)
        }
        HarborSettingsSection(DesktopInterfaceText.value("Resume")) {
            HarborSettingsToggle(DesktopInterfaceText.value("Resume where you left off"), note: DesktopInterfaceText.value("Pick up partly-watched episodes and movies at your saved spot. Anything watched past 80% always restarts. Turn this off to always start from the beginning, handy if you rewatch shows."), isOn: $resumePlayback)
            HarborSettingsToggle(DesktopInterfaceText.value("Ask to resume or start over"), isOn: $resumePrompt).disabled(!resumePlayback)
        }
        advisorySettings
        PlayerNextEpisodeSettings()
        PlayerAdSkipSettings()
        HarborSettingsSection("Búfer") {
            HarborSettingsChoice("Tamaño del búfer", selection: $preferences.options.bufferSize, choices: BufferSize.allCases.map { ($0.title, $0) })
            HarborSettingsToggle(DesktopInterfaceText.value("Slow or unstable connection"),
                                 note: DesktopInterfaceText.value("Reads up to ten minutes ahead. Uses more memory to help with an unstable connection."),
                                 isOn: $mpvBufferBoost)
                .disabled(preferences.options.bufferSize != .auto)
                .accessibilityIdentifier("settings-buffer-boost")
        }
    }

    /// Desktop's content advisory rows (`views/settings/player-layout-panel/index.tsx`, under "While you watch").
    @ViewBuilder private var advisorySettings: some View {
        HarborSettingsSection("While you watch", note: "Optional overlays that appear over the video.") {
            HarborSettingsToggle("Content advisory on start", note: "When a movie or episode starts, briefly show its IMDb parental guide (violence, profanity, substances, frightening scenes and more) with severity. Fades on its own.", isOn: $advisory.showToast)
                .accessibilityIdentifier("settings-content-advisory")
            if advisory.showToast {
                HarborSettingsChoice("Content advisory theme", selection: $advisory.theme, choices: [("Colored", ContentAdvisoryTheme.colored), ("Monochrome", .monochrome)], identifier: "settings-content-advisory-theme")
                Text(DesktopInterfaceText.value("Choose whether the content advisory appears in full color or a restrained monochrome tone.")).font(HarborTheme.font(13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HarborSettingsToggle("Show ignore title button", note: "Display a button on the content advisory card to permanently ignore the title.", isOn: $advisory.showIgnoreButton)
                    .accessibilityIdentifier("settings-content-advisory-ignore")
                if advisory.showIgnoreButton { ignoredTitlesRow }
            }
        }
    }

    /// Desktop's `AdvisoryIgnoreRow`: the titles ignored on this device, and a way to bring them back.
    private var ignoredTitlesRow: some View {
        let count = ContentAdvisoryIgnores.shared.count
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(DesktopInterfaceText.value("Ignored titles")).font(HarborTheme.font(14, weight: .semibold))
                Text(count == 0
                     ? DesktopInterfaceText.value("Titles you ignore on the advisory card never show it again.")
                     : DesktopInterfaceText.value("{count} titles will never show the content advisory again.", variables: ["count": "\(count)"]))
                    .font(HarborTheme.font(13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(DesktopInterfaceText.value("Restore")) { ContentAdvisoryIgnores.shared.clear() }
                .disabled(count == 0)
                .accessibilityIdentifier("settings-content-advisory-restore")
        }.frame(minHeight: 44)
    }

    @ViewBuilder private var videoSettings: some View {
        if let state { PlayerFrameCaptureButton(state: state) }
        PlayerSeekBarSettings()
        HarborSettingsSection("Reproductor") {
            HarborSettingsChoice("Decodificación de vídeo", selection: $hardwareDecoding, choices: HardwareDecoding.allCases.map { ($0.title, $0) })
                .accessibilityIdentifier("settings-hwdec")
            HarborSettingsChoice(DesktopInterfaceText.value("Picture quality"), selection: $mpvQuality, choices: mpvQualityChoices, localizeChoices: false, identifier: "settings-mpv-quality")
            Text(DesktopInterfaceText.value("Balance picture quality and performance. Changes apply to the next video you play."))
                .font(HarborTheme.font(12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HarborSettingsToggle(DesktopInterfaceText.value("HDR-to-SDR tonemapping"),
                                 note: DesktopInterfaceText.value("Maps HDR sources to SDR using bt.2446a. Recommended on SDR displays."),
                                 isOn: $playerHdrToSdr).accessibilityIdentifier("settings-hdr-to-sdr")
            PlayerColorHdrSettings()
        }
        HarborSettingsSection(DesktopInterfaceText.value("Stream quality in player")) {
            HarborSettingsToggle(DesktopInterfaceText.value("Show stream quality under the title"),
                                 note: DesktopInterfaceText.value("See the resolution, HDR format and audio while you watch."),
                                 isOn: $sources.showQualityInfo).accessibilityIdentifier("settings-quality-info")
            if sources.showQualityInfo {
                HarborSettingsChoice(DesktopInterfaceText.value("Quality badge style"), selection: $sources.qualityBadgeStyle,
                                     choices: [(DesktopInterfaceText.value("Bar"), "bar"), (DesktopInterfaceText.value("Chips"), "chips")],
                                     localizeChoices: false, identifier: "settings-quality-badge-style")
            }
        }
        HarborSettingsSection(DesktopInterfaceText.value("X-Ray (experimental)")) {
            HarborSettingsToggle(DesktopInterfaceText.value("Enable X-Ray"),
                                 note: DesktopInterfaceText.value("Adds an X-Ray button in the player to see the full cast with photos and tap through to any actor. Needs a TMDB key for photos and filmographies."),
                                 isOn: $sources.xrayEnabled).accessibilityIdentifier("settings-xray-enabled")
        }
        HarborSettingsSection(DesktopInterfaceText.value("Picture")) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(PicturePreset.allCases) { preset in
                    Button {
                        var next = preferences.options; next.applyPicturePreset(preset)
                        preferences.options = next
                    } label: {
                        Text(preset.title).font(HarborTheme.font(12, weight: .semibold))
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(HarborTheme.surface.opacity(0.4), in: .capsule)
                            .overlay { Capsule().stroke(HarborTheme.ink.opacity(0.1), lineWidth: 1) }
                    }.accessibilityHint(preset.description).accessibilityIdentifier("settings-picture-preset-\(preset.id)")
                }
            }
            dial(DesktopInterfaceText.value("Brightness"), value: $preferences.options.brightness, range: -50...50)
            dial(DesktopInterfaceText.value("Contrast"), value: $preferences.options.contrast, range: -50...50)
            dial(DesktopInterfaceText.value("Saturation"), value: $preferences.options.saturation, range: -50...50)
            dial(DesktopInterfaceText.value("Gamma"), value: $preferences.options.gamma, range: -50...50)
            dial(DesktopInterfaceText.value("Sharpen"), value: $preferences.options.sharpen, range: 0...2, step: 0.05)
            Button(DesktopInterfaceText.value("Reset picture")) {
                var next = preferences.options
                next.brightness = 0; next.contrast = 0; next.saturation = 0; next.gamma = 0; next.sharpen = 0
                preferences.options = next
            }
        }
        HarborSettingsSection(DesktopInterfaceText.value("Aspect ratio")) {
            HarborSettingsChoice(DesktopInterfaceText.value("Aspect ratio"), selection: $preferences.options.fit, choices: VideoFit.allCases.map { ($0.title, $0) })
                .accessibilityIdentifier("settings-video-fit")
            if preferences.options.fit == .zoom { dial(DesktopInterfaceText.value("Zoom"), value: $preferences.options.zoom, range: 0...1, step: 0.05) }
        }
    }

    @ViewBuilder private var audioSettings: some View {
        if let state {
            HarborSettingsSection(DesktopInterfaceText.value("Audio")) {
                tracks(state, type: "audio", property: "aid")
                HarborSettingsToggle(DesktopInterfaceText.value("Mute"), isOn: Binding(get: { state.muted }, set: { state.controller?.set("mute", $0 ? "yes" : "no") }))
                dial(DesktopInterfaceText.value("Volume"), value: Binding(get: { state.volume }, set: { preferences.options.volume = $0 }), range: 0...preferences.options.volumeCeiling, suffix: "%")
            }
        }
        HarborSettingsSection(DesktopInterfaceText.value("Audio languages"), note: DesktopInterfaceText.value("When a release ships multiple audio tracks, Harbor selects the first match from this list.")) {
            HarborLanguagesPicker(value: $preferences.options.audioLanguage, identifier: "settings-audio-languages")
        }
        HarborSettingsSection(DesktopInterfaceText.value("Audio")) {
            HarborSettingsToggle(DesktopInterfaceText.value("Normalize loudness"), note: DesktopInterfaceText.value("Evens out quiet dialogue and loud action scenes with a dynamic normalizer."), isOn: $preferences.options.audioNormalize)
                .accessibilityIdentifier("settings-audio-normalize")
            HarborSettingsToggle(DesktopInterfaceText.value("Mix surround sound down to stereo"), isOn: $preferences.options.stereo)
            HarborSettingsChoice(DesktopInterfaceText.value("Maximum volume boost"), selection: $preferences.options.volumeBoostMax,
                                 choices: PlaybackOptions.volumeBoostChoices.map { ("\(Int($0 * 100))%", $0) }, localizeChoices: false, identifier: "settings-volume-boost")
            Text(DesktopInterfaceText.value("How far you can boost past 100 percent on the volume bar. Higher settings can get very loud.")).font(HarborTheme.font(12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HarborSettingsChoice(DesktopInterfaceText.value("Sound profile"), selection: $preferences.options.audioProfile,
                                 choices: AudioProfile.allCases.map { ($0.label, $0.rawValue) }, identifier: "settings-audio-profile")
            Text(DesktopInterfaceText.value("Night mode gently compresses loud moments for late-night watching. Profiles take effect when the next track loads and stack with the normalizer."))
                .font(HarborTheme.font(12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        HarborSettingsSection(DesktopInterfaceText.value("Sync Offset")) {
            dial(DesktopInterfaceText.value("Sync Offset"), value: $preferences.options.audioDelay, range: -10...10, step: 0.1, suffix: " s")
            Button(DesktopInterfaceText.value("Reset sync")) { preferences.options.audioDelay = 0 }
        }
    }

    /// Desktop's community server dialog: blank uses Harbor's server, anything else must be an http or https address.
    private var communityServerSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text(DesktopInterfaceText.value("Leave this blank to use Harbor's own community server, or enter the address of a server you run yourself.")).font(HarborTheme.font(14)).foregroundStyle(.secondary)
                TextField(DesktopInterfaceText.value("https://sync.harbor.site"), text: $serverDraft)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).textFieldStyle(.roundedBorder)
                    .accessibilityLabel(DesktopInterfaceText.value("Server address"))
                if serverInvalid {
                    Text(DesktopInterfaceText.value("Enter a full http:// or https:// address, or leave blank to use Harbor's server.")).font(HarborTheme.font(13)).foregroundStyle(.red)
                }
                Text(DesktopInterfaceText.value("Private mode stops all contact with this server in either direction.")).font(HarborTheme.font(12)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .navigationTitle(DesktopInterfaceText.value("Community sync server")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(DesktopInterfaceText.value("Cancel")) { serverEditing = false } }
                    ToolbarItem(placement: .confirmationAction) { Button(DesktopInterfaceText.value("Save")) { saveCommunityServer() } }
                }
        }
    }

    private func saveCommunityServer() {
        guard let stored = CommunitySyncRules.storedServer(serverDraft) else { serverInvalid = true; return }
        communitySyncUrl = stored
        serverEditing = false
    }

    @ViewBuilder private var subtitlesSettings: some View {
        if state == nil {
            HarborSettingsSection("Sincronización automática", note: "Analiza el audio en segundo plano para ajustar subtítulos externos SRT/VTT en UTF-8 o UTF-16. Si no hay una coincidencia fiable, conserva el original.") {
                HarborSettingsToggle("Sincronizar subtítulos con el audio", isOn: $subtitleAutoSync)
                if subtitleAutoSync {
                    HarborSettingsToggle(DesktopInterfaceText.value("Drift monitor"), note: DesktopInterfaceText.value("Keeps watching through playback and gently re-nudges the timing if the subtitle slips out of sync partway through."), isOn: $autoSyncDrift)
                        .accessibilityIdentifier("subtitle-settings-drift")
                    HarborSettingsToggle(DesktopInterfaceText.value("Match subtitles across languages (experimental)"),
                                         note: DesktopInterfaceText.value("When the audio and subtitle use different languages, Harbor compares a release-matched subtitle in the audio language. It only offers a fix unless every safety check is measured."),
                                         isOn: $subtitleAutoSyncPivot)
                        .accessibilityIdentifier("subtitle-settings-cross-language")
                }
            }
        }
        HarborSettingsSection(DesktopInterfaceText.value("Community sync"), note: DesktopInterfaceText.value("Find and share verified timing corrections for matching video and subtitle files. Turn on Private mode to stop community lookups and contributions.")) {
            HarborSettingsToggle(DesktopInterfaceText.value("Use community corrections"), note: DesktopInterfaceText.value("Check the shared database first. When this exact subtitle has already been synced by someone else, yours snaps into place with no analysis."), isOn: $subtitleAutoSyncCrowd)
                .disabled(communitySyncOptOut)
            if communitySyncOptOut {
                Text(DesktopInterfaceText.value("Private mode is on, so nothing is looked up or contributed from this device.")).font(HarborTheme.font(12)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(DesktopInterfaceText.value("Community sync server")).font(HarborTheme.font(14, weight: .semibold))
                Text(communitySyncUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                     ? DesktopInterfaceText.value("Harbor uses its own community server. You can point it at a server you run yourself.")
                     : communitySyncUrl.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(HarborTheme.font(13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(communitySyncUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? DesktopInterfaceText.value("Use my own server") : DesktopInterfaceText.value("Change server")) {
                    serverDraft = communitySyncUrl; serverInvalid = false; serverEditing = true
                }.frame(minHeight: 44).accessibilityIdentifier("settings-community-sync-server")
                    .sheet(isPresented: $serverEditing) { communityServerSheet }
            }
            HarborSettingsToggle(DesktopInterfaceText.value("Private mode"), note: DesktopInterfaceText.value("Never contact the community server in either direction. Nothing is looked up and nothing is contributed from this device."), isOn: $communitySyncOptOut)
        }
        if let state {
            HarborSettingsSection(DesktopInterfaceText.value("Subtitles")) {
                SubtitleTracksView(state: state, embedded: true)
            }
            HarborSettingsSection(DesktopInterfaceText.value("Subtitle FPS")) {
                NavigationLink { SubtitleTimingView(state: state) } label: {
                    Label { Text(DesktopInterfaceText.value("Subtitle FPS")) } icon: { Image("player-subtitle-fps").resizable().scaledToFit().frame(width: 20, height: 20) }
                }
                if state.subtitleChanging { ProgressView(DesktopInterfaceText.value("Saving")) }
            }
        }
        HarborSettingsSection(DesktopInterfaceText.value("Subtitle sources")) {
            NavigationLink { SubtitleProvidersSettingsView(owner: MetadataPreferences.shared.settingsOwner ?? "guest").toolbar(.visible, for: .navigationBar) } label: {
                SettingsRow(title: DesktopInterfaceText.value("Subtitle sources"), icon: "ui-customize-subtitles")
            }.background(HarborTheme.surface.opacity(0.65), in: .rect(cornerRadius: 12)).accessibilityIdentifier("settings-subtitle-sources")
        }
        HarborSettingsSection(DesktopInterfaceText.value("Choosing a track")) {
            NavigationLink { SubtitleSelectionSettingsView() } label: { SettingsRow(title: DesktopInterfaceText.value("Choosing a track"), icon: "ui-customize-subtitles") }
                .background(HarborTheme.surface.opacity(0.65), in: .rect(cornerRadius: 12)).accessibilityIdentifier("settings-subtitle-selection")
        }
        HarborSettingsSection(DesktopInterfaceText.value("Subtitle languages"), note: DesktopInterfaceText.value("Harbor looks for subtitles in this order. Put your preferred language first.")) {
            HarborLanguagesPicker(value: $preferences.options.subtitleLanguage, identifier: "settings-subtitle-languages")
            HarborSettingsToggle(DesktopInterfaceText.value("Start with subtitles off"), isOn: $preferences.options.subtitlesOff)
            HarborSettingsToggle(DesktopInterfaceText.value("Hide sound effects and speaker names"), isOn: $preferences.options.hideSDH)
        }
        HarborSettingsSection(DesktopInterfaceText.value("Dual subtitles"), note: DesktopInterfaceText.value("Show two subtitle languages at once. Useful for learning a language or watching together.")) {
            HarborSettingsChoice(DesktopInterfaceText.value("Second subtitle language"), selection: secondaryLanguage, choices: [(DesktopInterfaceText.value("Off"), "")] + SubtitleLanguages.allCodes.map { (SubtitleLanguages.preferenceName($0), $0) })
                .accessibilityIdentifier("settings-secondary-subtitle-language")
            if !secondaryLanguage.wrappedValue.isEmpty {
                HarborSettingsChoice(DesktopInterfaceText.value("Where it shows"), selection: $preferences.options.secondarySubtitlePlacement, choices: [(DesktopInterfaceText.value("Top of the screen"), "top"), (DesktopInterfaceText.value("Above the main line"), "bottom")])
            }
        }
        HarborSettingsSection(DesktopInterfaceText.value("Sync Offset")) {
            dial(DesktopInterfaceText.value("Sync Offset"), value: $preferences.options.subtitleDelay, range: -10...10, step: 0.1, suffix: " s")
        }
        HarborSettingsSection(DesktopInterfaceText.value("Show subtitle sync indicator"),
                              note: DesktopInterfaceText.value("Puts the current offset on screen while you nudge subtitle timing with Z or X, so you can see how far you have shifted them.")) {
            HarborSettingsToggle(DesktopInterfaceText.value("Show subtitle sync indicator"), isOn: $preferences.options.subOffsetIndicator)
                .accessibilityIdentifier("settings-sub-offset-indicator")
            if preferences.options.subOffsetIndicator {
                HarborSettingsChoice(DesktopInterfaceText.value("Position"), selection: $preferences.options.subOffsetPosition,
                                     choices: SubtitleOffsetPosition.allCases.map { (DesktopInterfaceText.value($0.label), $0.rawValue) }, identifier: "settings-sub-offset-position")
                HarborSettingsChoice(DesktopInterfaceText.value("Size"), selection: $preferences.options.subOffsetSize,
                                     choices: SubtitleOffsetSize.allCases.map { (DesktopInterfaceText.value($0.label), $0.rawValue) }, identifier: "settings-sub-offset-size")
            }
        }
        HarborSettingsSection(DesktopInterfaceText.value("Show subtitles in Picture-in-Picture"),
                              note: DesktopInterfaceText.value("Keeps subtitles visible when the player shrinks into the small floating window. Turn off to hide them there.")) {
            HarborSettingsToggle(DesktopInterfaceText.value("Show subtitles in Picture-in-Picture"), isOn: $preferences.options.subShowInPip)
                .accessibilityIdentifier("settings-sub-show-in-pip")
        }
        HarborSettingsSection(DesktopInterfaceText.value("Subtitle style"), note: DesktopInterfaceText.value("Adjust the text and background. The preview shows your changes as you make them.")) {
            SubtitleStylePreview(options: preferences.options)
            SubtitleLookPresetsView(options: $preferences.options)
            Text(DesktopInterfaceText.value("Background")).font(HarborTheme.font(14, weight: .semibold))
            SubtitleBackgroundChoices(selection: $preferences.options.subtitleStyle)
            Text(DesktopInterfaceText.value("Font")).font(HarborTheme.font(14, weight: .semibold))
            SubtitleFontChoices(selection: $preferences.options.subtitleFont)
            HarborSettingsChoice(DesktopInterfaceText.value("Styled (ASS) subtitles"), selection: $preferences.options.subtitleASS, choices: [(DesktopInterfaceText.value("Keep original"), "no"), (DesktopInterfaceText.value("Override embedded styles"), "yes"), (DesktopInterfaceText.value("Resize only"), "scale"), (DesktopInterfaceText.value("Use my style"), "force"), (DesktopInterfaceText.value("No styling"), "strip")])
            HarborSettingsToggle(DesktopInterfaceText.value("Bold text"), isOn: $preferences.options.subtitleBold)
            dial(DesktopInterfaceText.value("Size"), value: $preferences.options.subtitleSize, range: 16...120)
            dial(DesktopInterfaceText.value("Letter spacing"), value: $preferences.options.subtitleSpacing, range: 0...12)
            dial(DesktopInterfaceText.value("Opacity"), value: $preferences.options.subtitleOpacity, range: 0.2...1, step: 0.05)
            dial(DesktopInterfaceText.value("Distance from bottom"), value: Binding(get: { 100 - preferences.options.subtitlePosition }, set: { preferences.options.subtitlePosition = 100 - $0 }), range: 0...100, suffix: "%")
            HarborSettingsChoice(DesktopInterfaceText.value("Alignment"), selection: $preferences.options.subtitleAlignment, choices: [(DesktopInterfaceText.value("Left"), "left"), (DesktopInterfaceText.value("Center"), "center"), (DesktopInterfaceText.value("Right"), "right")])
            SubtitleColorField(title: DesktopInterfaceText.value("Text color"), value: $preferences.options.subtitleColor, fallback: "#FFFFFF")
            if preferences.options.subtitleStyle == "outline" {
                dial(DesktopInterfaceText.value("Outline thickness"), value: $preferences.options.borderSize, range: 1...6, step: 0.5)
                SubtitleColorField(title: DesktopInterfaceText.value("Outline color"), value: $preferences.options.borderColor, fallback: "#000000")
            }
            if preferences.options.subtitleStyle == "box" {
                SubtitleColorField(title: DesktopInterfaceText.value("Box color"), value: $preferences.options.subtitleBoxColor, fallback: "#000000")
                dial(DesktopInterfaceText.value("Background opacity"), value: $preferences.options.boxOpacity, range: 0...1, step: 0.05)
            }
            Button(DesktopInterfaceText.value("Reset subtitle style")) {
                let original = PlaybackOptions()
                var next = preferences.options
                next.subtitleSize = original.subtitleSize; next.subtitlePosition = original.subtitlePosition
                next.subtitleBold = false; next.subtitleStyle = original.subtitleStyle
                next.subtitleAlignment = original.subtitleAlignment
                next.subtitleColor = original.subtitleColor; next.borderColor = original.borderColor
                next.borderSize = original.borderSize; next.boxOpacity = original.boxOpacity
                next.subtitleOpacity = original.subtitleOpacity
                next.subtitleFont = original.subtitleFont; next.subtitleSpacing = original.subtitleSpacing
                next.subtitleBoxColor = original.subtitleBoxColor
                preferences.options = next
            }
        }
    }

    private func tracks(_ state: PlayerState, type: String, property: String) -> some View {
        ForEach(state.tracks.filter { $0.type == type }) { track in
            Button { state.controller?.set(property, String(track.id)) } label: {
                HStack { Text(track.label).fixedSize(horizontal: false, vertical: true); Spacer(); if (property == "sid" ? track.mainSelection == 0 : track.selected) { Image("music-check").resizable().scaledToFit().frame(width: 20, height: 20).accessibilityHidden(true) } }
            }
            .disabled(type == "sub" && state.subtitleChanging)
        }
    }

    private func dial(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double = 1, suffix: String = "") -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(title).font(HarborTheme.font(14, weight: .semibold)).fixedSize(horizontal: false, vertical: true); Spacer(); Text(value.wrappedValue.formatted(.number.precision(.fractionLength(0...2))) + suffix).monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: value, in: range, step: step).accessibilityLabel(title)
        }
    }
    private var secondaryLanguage: Binding<String> {
        Binding(get: { SubtitleLanguages.preferredCodes(preferences.options.secondarySubtitleLanguage).first ?? "" },
                set: { preferences.options.secondarySubtitleLanguage = $0 })
    }
    private func color(_ value: Binding<String>) -> Binding<Color> {
        Binding(get: { Color(hex: value.wrappedValue) }, set: { value.wrappedValue = $0.rgbHex })
    }
}

extension Color {
    init(hex: String) {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0xFFFFFF
        self.init(.sRGB, red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
    var rgbHex: String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 1
        guard UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return "#FFFFFF" }
        return String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }
}
