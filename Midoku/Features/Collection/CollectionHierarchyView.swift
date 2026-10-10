import SwiftUI

/// Both pickers include nested entries. Moving changes only containment, not
/// source links, update settings, covers, categories or physical chapter data.
struct MCEntryPlacementView: View {
    enum Mode {
        case move(UUID)
        case addInside(UUID)
    }
    let mode: Mode
    @Environment(\.dismiss) private var dismiss
    @State private var store = MCCollectionStore.shared
    @State private var query = ""
    @State private var newTitle = ""

    private var candidates: [MCPersonalEntry] {
        store.library.entries.filter { entry in
            let allowed: Bool
            switch mode {
            case .move(let id): allowed = store.library.canMove(id, into: entry.id) && store.library.entry(id)?.parentEntryID != entry.id
            case .addInside(let parent): allowed = store.library.canMove(entry.id, into: parent) && entry.parentEntryID != parent
            }
            return allowed && (query.isEmpty || store.library.title(entry).localizedCaseInsensitiveContains(query)
                || store.library.parentPath(of: entry)?.localizedCaseInsensitiveContains(query) == true)
        }.sorted { store.library.title($0).localizedStandardCompare(store.library.title($1)) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                if case .addInside(let parent) = mode {
                    Section("Create nested title") {
                        TextField("Title", text: $newTitle)
                        Button("Create title", systemImage: "plus") {
                            if store.perform({ state in
                                let id = try state.library.createManual(title: newTitle)
                                try state.library.moveEntry(id, into: parent)
                            }) { dismiss() }
                        }.disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                Section {
                    ForEach(candidates) { entry in
                        Button {
                            if store.perform({ state in
                                switch mode {
                                case .move(let id): try state.library.moveEntry(id, into: entry.id)
                                case .addInside(let parent): try state.library.moveEntry(entry.id, into: parent)
                                }
                            }) { dismiss() }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(store.library.title(entry)).foregroundStyle(.primary)
                                if let path = store.library.parentPath(of: entry) {
                                    Text(path).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text(sectionTitle)
                } footer: {
                    Text("Titles keep their chapters, progress and Get new chapters settings when moved.")
                }
            }
            .searchable(text: $query, prompt: "Search titles")
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .mcErrors(store)
        }
        .midokuAccent()
    }

    private var navigationTitle: String {
        switch mode { case .move: "Add to entry"; case .addInside: "Add nested title" }
    }
    private var sectionTitle: String {
        switch mode { case .move: "Choose parent title"; case .addInside: "Move an existing title here" }
    }
}
