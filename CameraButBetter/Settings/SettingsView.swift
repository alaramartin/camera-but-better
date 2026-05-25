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
                    Text("AI Feedback")
                } footer: {
                    Text("Tap the sparkles button to analyze the current frame.")
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
