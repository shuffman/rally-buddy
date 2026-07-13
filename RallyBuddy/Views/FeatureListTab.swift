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
                            HStack(spacing: 6) {
                                Text(feature.displayLabel)
                                if feature.type == .tightCorner {
                                    HStack(spacing: -4) {
                                        ForEach(0..<feature.chevronCount, id: \.self) { _ in
                                            Image(systemName: "chevron.right")
                                        }
                                    }
                                    .font(.caption.bold())
                                    .foregroundStyle(.red)
                                }
                                if feature.isSuggested {
                                    Text("SUGGESTED")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(.orange.opacity(0.2), in: Capsule())
                                        .foregroundStyle(.orange)
                                }
                            }
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
                    .swipeActions(edge: .leading) {
                        if feature.isSuggested {
                            Button {
                                feature.isSuggested = false
                            } label: {
                                Label("Confirm", systemImage: "checkmark")
                            }
                            .tint(.green)
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
