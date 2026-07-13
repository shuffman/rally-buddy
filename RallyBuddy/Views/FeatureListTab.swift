import SwiftData
import SwiftUI

struct FeatureListTab: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RoadFeature.createdAt, order: .reverse)
    private var features: [RoadFeature]

    var body: some View {
        NavigationStack {
            List {
                ForEach(features) { feature in
                    HStack {
                        Image(systemName: feature.type.systemImage)
                            .foregroundStyle(feature.type.tint)
                        VStack(alignment: .leading) {
                            Text(feature.type.label)
                            if !feature.note.isEmpty {
                                Text(feature.note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if feature.bearing != nil {
                            Image(systemName: "arrow.up.circle")
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("One direction only")
                        }
                    }
                }
                .onDelete(perform: delete)
            }
            .overlay {
                if features.isEmpty {
                    ContentUnavailableView(
                        "No features yet",
                        systemImage: "mappin.slash",
                        description: Text("Tap the map to mark passing lanes, residential zones, and tight corners.")
                    )
                }
            }
            .navigationTitle("Features")
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(features[index])
        }
    }
}
