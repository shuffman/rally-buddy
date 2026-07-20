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

    private var trimmedKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Claude API key (optional)", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Optional. With a key, Claude writes natural linked pace notes; without one, a built-in template writes basic callouts. Clear the field to remove a saved key. Used only while generating; stored in the Keychain. Drives always replay the saved script offline.")
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
                    } else if trimmedKey.isEmpty {
                        Text("\(featureCount) features along this route. No API key — the built-in template will be used.")
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
        let key = trimmedKey
        Task {
            do {
                if key.isEmpty {
                    // Empty field removes any previously saved key.
                    KeychainStore.deleteAPIKey()
                    lines = try CalloutPlanner.templateScript(
                        route: route,
                        features: features
                    )
                } else {
                    lines = try await CalloutPlanner.generateScript(
                        route: route,
                        features: features,
                        apiKey: key
                    )
                    KeychainStore.saveAPIKey(key)
                }
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
