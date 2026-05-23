import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = ""
    @State private var hasStoredKey: Bool = false
    @State private var savedAcknowledgement: String?
    @State private var isKeyVisible: Bool = false
    @FocusState private var keyFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Group {
                            if isKeyVisible {
                                TextField("Paste Gemini API key", text: $apiKey)
                            } else {
                                SecureField("Paste Gemini API key", text: $apiKey)
                            }
                        }
                        .textContentType(.password)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                        .focused($keyFieldFocused)

                        Button {
                            isKeyVisible.toggle()
                            keyFieldFocused = true
                        } label: {
                            Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isKeyVisible ? "Hide API key" : "Show API key")
                    }

                    Button("Save Key") { save() }
                        .disabled(apiKey.isEmpty)

                    if hasStoredKey {
                        Button("Remove Stored Key", role: .destructive) { remove() }
                    }
                } header: {
                    Text("Gemini API Key")
                } footer: {
                    Text(hasStoredKey
                        ? "A key is stored in the iOS Keychain on this device."
                        : "No key stored yet. AI feedback is disabled until you add one.")
                }

                if let savedAcknowledgement {
                    Section {
                        Text(savedAcknowledgement)
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }
                }

                Section("About") {
                    LabeledContent("Model", value: Constants.Gemini.model)
                    LabeledContent("Mode", value: "On-demand")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        hasStoredKey = KeychainService.shared.hasAPIKey
        apiKey = ""
        isKeyVisible = false
    }

    private func save() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if KeychainService.shared.saveAPIKey(trimmed) {
            hasStoredKey = true
            apiKey = ""
            savedAcknowledgement = "Key saved to Keychain."
        } else {
            savedAcknowledgement = "Failed to save key."
        }
    }

    private func remove() {
        KeychainService.shared.deleteAPIKey()
        hasStoredKey = false
        savedAcknowledgement = "Key removed."
    }
}
