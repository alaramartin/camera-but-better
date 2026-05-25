import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
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
