import SwiftData
import SwiftUI

/// Generate, preview, and edit the AI co-driver script for a saved route.
/// One Claude API call at planning time; the saved lines replay offline
/// during drives via AlertEngine.
struct CoDriverScriptSheet: View {
    let route: Route
    let features: [RoadFeature]

    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = KeychainStore.loadAPIKey() ?? ""
    @State private var lines: [PaceNote] = []
    @State private var isGenerating = false
    @State private var errorMessage: String?

    private var featureCount: Int {
        CalloutPlanner.orderedFeatures(route: route, features: features).count
    }

    var body: some View {
        NavigationStack {
            Form {
                if KeychainStore.loadAPIKey() == nil {
                    Section {
                        SecureField("Claude API key", text: $apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } footer: {
                        Text("Used only while generating; stored in the Keychain. Drives replay the saved script offline.")
                    }
                }

                Section {
                    Button {
                        generate()
                    } label: {
                        if isGenerating {
                            HStack {
                                ProgressView()
                                Text("Writing pace notes…")
                            }
                        } else {
                            Label(
                                lines.isEmpty ? "Generate Script" : "Regenerate Script",
                                systemImage: "waveform"
                            )
                        }
                    }
                    .disabled(isGenerating || featureCount == 0)
                } footer: {
                    if featureCount == 0 {
                        Text("No confirmed features along this route yet. Mark features or run Detect Features first.")
                    } else {
                        Text("\(featureCount) features along this route.")
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }

                if !lines.isEmpty {
                    Section("Pace notes (editable)") {
                        ForEach($lines) { $note in
                            TextField("Callout", text: $note.text, axis: .vertical)
                        }
                        .onDelete { lines.remove(atOffsets: $0) }
                    }
                }
            }
            .navigationTitle("Co-Driver Script")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(lines.isEmpty || isGenerating)
                }
            }
            .onAppear {
                lines = route.paceNotes
            }
        }
    }

    private func generate() {
        errorMessage = nil
        isGenerating = true
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let notes = try await CalloutPlanner.generateScript(
                    route: route,
                    features: features,
                    apiKey: key
                )
                KeychainStore.saveAPIKey(key)
                lines = notes
            } catch {
                errorMessage = error.localizedDescription
            }
            isGenerating = false
        }
    }

    private func save() {
        route.setPaceNotes(
            lines.filter {
                !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        )
        dismiss()
    }
}
