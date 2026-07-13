import CoreLocation
import SwiftData
import SwiftUI

struct AddFeatureSheet: View {
    let coordinate: CLLocationCoordinate2D
    /// The driver's current direction of travel, if known.
    let course: Double?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var type: RoadFeatureType = .tightCorner
    @State private var note = ""
    @State private var currentDirectionOnly = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $type) {
                    ForEach(RoadFeatureType.allCases) { type in
                        Label(type.label, systemImage: type.systemImage)
                            .tag(type)
                    }
                }
                .pickerStyle(.inline)

                TextField("Note (optional)", text: $note)

                if course != nil {
                    Toggle(
                        "Only for current direction of travel",
                        isOn: $currentDirectionOnly
                    )
                }
            }
            .navigationTitle("Mark Feature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    private func save() {
        let feature = RoadFeature(
            type: type,
            coordinate: coordinate,
            bearing: currentDirectionOnly ? course : nil,
            note: note
        )
        modelContext.insert(feature)
        dismiss()
    }
}
