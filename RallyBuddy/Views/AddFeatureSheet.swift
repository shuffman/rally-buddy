import CoreLocation
import SwiftData
import SwiftUI

/// Marks a feature at a tapped map point. Map-tap marking is a parked-car
/// activity, so there is no direction-of-travel option here — a tapped point
/// isn't somewhere the driver is heading. Quick-marks made while driving get
/// their bearing from the live course automatically (see AppServices.quickMark).
struct AddFeatureSheet: View {
    let coordinate: CLLocationCoordinate2D

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var type: RoadFeatureType = .tightCorner
    @State private var note = ""
    @State private var severity = 2

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

                if type == .tightCorner {
                    Picker("How tight?", selection: $severity) {
                        Text("›  Mild").tag(1)
                        Text("››  Tight").tag(2)
                        Text("›››  Hairpin").tag(3)
                    }
                    .pickerStyle(.segmented)
                }

                TextField("Note (optional)", text: $note)
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
            bearing: nil,
            note: note,
            severity: type == .tightCorner ? severity : 2
        )
        modelContext.insert(feature)
        dismiss()
    }
}
