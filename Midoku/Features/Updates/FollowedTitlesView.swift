import SwiftUI

struct MCFollowedTitlesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = MCCollectionStore.shared
    @State private var query = ""

    private var entries: [MCPersonalEntry] {
        store.library.entries.filter { entry in
            entry.links.contains(where: \.followsNewChapters) &&
                (query.isEmpty || store.library.title(entry).localizedCaseInsensitiveContains(query))
        }.sorted { store.library.title($0).localizedStandardCompare(store.library.title($1)) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(entries) { entry in
                        HStack(spacing: 12) {
                            MCEntryCover(entry: entry).frame(width: 40, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(store.library.title(entry)).font(.subheadline.weight(.medium))
                                if let path = store.library.parentPath(of: entry) {
                                    Text(path).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button(role: .destructive) { stopFollowing(entry.id) } label: {
                                Image(systemName: "minus.circle").font(.title3).frame(width: 44, height: 44)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Stop getting new chapters for \(store.library.title(entry))")
                        }
                        .swipeActions {
                            Button("Stop updates", role: .destructive) { stopFollowing(entry.id) }
                        }
                    }
                } footer: {
                    Text("Removing a title turns off Get new chapters for that title. Its nested titles keep their own settings.")
                }
            }
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView(query.isEmpty ? "No followed titles" : "No matches", systemImage: "bell.slash")
                }
            }
            .searchable(text: $query, prompt: "Search followed titles")
            .navigationTitle("Get new chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .mcErrors(store)
        }
        .midokuAccent()
    }

    private func stopFollowing(_ id: UUID) {
        store.perform { state in
            try state.library.editEntry(id) { entry in
                for index in entry.links.indices { entry.links[index].followsNewChapters = false }
            }
        }
    }
}
