import SwiftUI

/// Lists titles that look like the same series. Merging uses the regular grouping editor,
/// which keeps physical chapters, progress, sources and bookmarks.
struct MCDuplicateFinderView: View {
    let merge: ([UUID]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var store = MCCollectionStore.shared
    @AppStorage("Midoku.ignoredDuplicateGroups.v1") private var ignoredData = Data()

    private var ignored: Set<String> {
        Set((try? JSONDecoder().decode([String].self, from: ignoredData)) ?? [])
    }

    private func signature(_ ids: [UUID]) -> String {
        ids.map(\.uuidString).sorted().joined(separator: ",")
    }

    private var groups: [[UUID]] {
        let ignored = ignored
        return store.library.duplicateGroups().filter { !ignored.contains(signature($0)) }
    }

    var body: some View {
        NavigationStack {
            let groups = groups
            List {
                ForEach(groups, id: \.self) { group in
                    Section {
                        ForEach(group, id: \.self) { id in
                            if let entry = store.library.entry(id) { row(entry) }
                        }
                        HStack {
                            Button("Merge or group…", systemImage: "rectangle.stack.badge.plus") {
                                merge(group)
                                dismiss()
                            }
                            Spacer()
                            Button("Not duplicates") { ignore(group) }
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .font(.subheadline.weight(.medium))
                    }
                }
            }
            .overlay {
                if groups.isEmpty {
                    ContentUnavailableView("No duplicates found", systemImage: "checkmark.seal",
                        description: Text("Titles with the same name, ignoring case, accents, punctuation and notes in brackets, appear here."))
                }
            }
            .navigationTitle("Duplicates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                if !ignored.isEmpty {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Show hidden") { ignoredData = Data() }
                    }
                }
            }
        }
        .midokuAccent()
    }

    private func row(_ entry: MCPersonalEntry) -> some View {
        HStack(spacing: 12) {
            MCEntryCover(entry: entry).frame(width: 40, height: 60).clipShape(RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 3) {
                Text(store.library.title(entry)).font(.body.weight(.medium)).lineLimit(2)
                if let path = store.library.parentPath(of: entry) {
                    Text(path).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                let sources = entry.links.compactMap { store.library.listing($0.listingID)?.identity.connectionID }
                    .map(store.sourceName)
                Text("\(store.chapterCount(entryID: entry.id)) chapters · \(sources.isEmpty ? "No source" : sources.joined(separator: ", "))")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func ignore(_ group: [UUID]) {
        var values = ignored
        values.insert(signature(group))
        ignoredData = (try? JSONEncoder().encode(Array(values))) ?? Data()
    }
}
