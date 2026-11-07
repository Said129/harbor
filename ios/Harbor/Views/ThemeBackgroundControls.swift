import SwiftUI
import UIKit
import PhotosUI

/// Draws the saved background behind the whole app, with Desktop's dim overlay
/// (canvas color at the dim opacity). Screens use a clear background while it is active.
struct ThemeBackdrop: View {
    @State private var image: UIImage?

    var body: some View {
        let preferences = ThemePreferences.shared
        ZStack {
            if preferences.hasBackgroundImage {
                preferences.color("canvas")
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                }
                preferences.color("canvas").opacity(preferences.backgroundDim)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: preferences.backgroundRevision) { loadImage() }
    }

    private func loadImage() {
        guard ThemePreferences.shared.hasBackgroundImage,
              let data = ThemeBackgroundStore.shared.read(ThemeBackgroundStore.activeName) else {
            image = nil
            return
        }
        image = UIImage(data: data)
    }
}

/// Settings controls for the background image: pick, remove and dim.
struct ThemeBackgroundSection: View {
    @Bindable var preferences: ThemePreferences
    @State private var chosenPhoto: PhotosPickerItem?
    @State private var error: String?

    var body: some View {
        HarborSettingsSection(DesktopInterfaceText.value("Background image"), note: DesktopInterfaceText.value("Drop a wallpaper behind the app. The dim slider keeps text readable.")) {
            if !preferences.hasBackgroundImage {
                Text(DesktopInterfaceText.value("No background image")).font(HarborTheme.font(15.5)).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                PhotosPicker(selection: $chosenPhoto, matching: .images) {
                    Text(DesktopInterfaceText.value(preferences.hasBackgroundImage ? "Replace image" : "Choose image"))
                }.buttonStyle(HarborAccountButtonStyle()).accessibilityIdentifier("theme-background-choose")
                if preferences.hasBackgroundImage {
                    Button(DesktopInterfaceText.value("Remove")) {
                        error = nil
                        preferences.clearBackgroundImage()
                    }.buttonStyle(HarborAccountButtonStyle()).accessibilityIdentifier("theme-background-remove")
                }
            }
            Text(DesktopInterfaceText.value("JPEG / PNG / WebP. Big files auto-compress to fit.")).font(HarborTheme.font(13)).foregroundStyle(.secondary)
            if preferences.hasBackgroundImage {
                HStack(spacing: 12) {
                    Text(DesktopInterfaceText.value("Dim overlay")).font(HarborTheme.font(15.5))
                    Slider(value: $preferences.backgroundDim, in: 0...1, step: 0.05)
                        .accessibilityLabel(DesktopInterfaceText.value("Dim overlay")).accessibilityIdentifier("theme-background-dim")
                    Text("\(Int((preferences.backgroundDim * 100).rounded()))%").font(HarborTheme.font(15.5, weight: .semibold)).monospacedDigit()
                }
            }
            if let error {
                Text(error).font(HarborTheme.font(15.5)).foregroundStyle(ThemePreferences.shared.color("danger"))
            }
        }
        .task(id: chosenPhoto) { await importPhoto() }
    }

    private func importPhoto() async {
        guard let chosenPhoto else { return }
        do {
            let data = try await chosenPhoto.loadTransferable(type: Data.self)
            try Task.checkCancellation()
            guard let data else {
                error = DesktopInterfaceText.value("Couldn't read that image. Try a different file.")
                return
            }
            error = preferences.setBackgroundImage(from: data)
                ? nil
                : DesktopInterfaceText.value("Couldn't compress this image small enough. Try a different photo or crop it down.")
        } catch is CancellationError {
            return
        } catch {
            self.error = DesktopInterfaceText.value("Couldn't read that image. Try a different file.")
        }
    }
}
