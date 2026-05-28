import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var overlaySettings: OverlaySettings

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Aspect Ratio", selection: $overlaySettings.aspectRatio) {
                        ForEach(PreviewAspectRatio.allCases) { ratio in
                            Text(ratio.label).tag(ratio)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Composition")
                } footer: {
                    Text("Frames the preview and crops captured photos to this ratio.")
                }

                Section {
                    Picker("Format", selection: $overlaySettings.photoFormat) {
                        ForEach(PhotoFormat.allCases) { format in
                            Text(format.label).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Photo Format")
                } footer: {
                    Text("RAW saves Apple ProRAW (DNG) at full sensor resolution. Aspect ratio crop is ignored for RAW captures.")
                }

                Section {
                    LabeledContent("Provider", value: "OpenRouter")
                    LabeledContent("Model", value: Constants.OpenRouter.model)
                    LabeledContent("Mode", value: "On-demand")
                } header: {
                    Text("Primary AI Feedback")
                } footer: {
                    Text("Tap the sparkles button to analyze the current frame.")
                }

                Section {
                    LabeledContent("Provider", value: "Google AI Studio")
                    LabeledContent("Model", value: Constants.Gemini.model)
                } header: {
                    Text("Fallback")
                } footer: {
                    Text("If the primary model is rate-limited or unavailable, tap Switch to Gemini on the error to retry with this model.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
