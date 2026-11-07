import SwiftUI

/// Desktop's TheIntroDB key on the intros tab (`views/settings/quality-panel/intros-tab.tsx`). Optional: a key only
/// raises the rate limit. It is kept in the Keychain of the profile, next to the OMDb and MDBList keys.
struct TheIntroDBKeyField: View {
    @State private var store: ProviderKeyStore
    @State private var draft = ""
    @State private var error: String?
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }

    init(owner: String) { _store = State(initialValue: ProviderKeyStore.forOwner(owner)) }

    private var saved: String { store.key(.theIntroDb) }
    private var dirty: Bool { draft.trimmingCharacters(in: .whitespacesAndNewlines) != saved }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(text("TheIntroDB · intro and credits timing")).font(HarborTheme.font(16, weight: .semibold))
                Circle().fill(saved.isEmpty ? Color.secondary.opacity(0.4) : Color.green).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(text(saved.isEmpty ? "Not set" : "Saved")).font(.footnote).foregroundStyle(.secondary)
            }
            SecureField(text("Paste your TheIntroDB API key"), text: $draft)
                .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive().submitLabel(.done).onSubmit { save() }
                .padding(.horizontal, 12).frame(minHeight: 48).background(HarborTheme.surface, in: .rect(cornerRadius: 10))
                .accessibilityIdentifier("theintrodb-key")
            HStack(spacing: 14) {
                Button(text(dirty || saved.isEmpty ? "Save" : "Saved")) { save() }
                    .buttonStyle(HarborAccountButtonStyle(primary: true))
                    .disabled(!dirty || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("theintrodb-key-save")
                if !saved.isEmpty {
                    Button(text("Remove"), role: .destructive) { remove() }.frame(minHeight: 44).accessibilityIdentifier("theintrodb-key-remove")
                }
                Spacer(minLength: 0)
                Link("theintrodb.org", destination: URL(string: "https://theintrodb.org")!).font(.footnote).underline().frame(minHeight: 44)
            }
            Text(text("Optional. TheIntroDB answers without a key, but a key raises your rate limit so timing keeps arriving when you binge. Get one at"))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
        }
        .padding(14).background(HarborTheme.surface.opacity(0.5), in: .rect(cornerRadius: 12))
        .task { load() }
        .task(id: saved) { draft = saved }
    }

    private func load() {
        do { if !store.ready { try store.load() } } catch { self.error = safeMessage(error) }
    }
    private func save() {
        do { try store.set(draft, for: .theIntroDb); error = nil } catch { self.error = safeMessage(error) }
    }
    private func remove() {
        do { try store.set("", for: .theIntroDb); draft = ""; error = nil } catch { self.error = safeMessage(error) }
    }
}
