import SwiftUI

struct UpdatesHistoryView: View {
    private enum Page: String, CaseIterable {
        case updates = "Updates"
        case history = "History"
    }

    @State private var page = Page.updates

    var body: some View {
        VStack(spacing: 0) {
            Picker("Updates and history", selection: $page) {
                ForEach(Page.allCases, id: \.self) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if page == .updates {
                MangaUpdatesView()
            } else {
                HistoryView()
            }
        }
        .navigationTitle("Updates")
        .navigationBarTitleDisplayMode(.inline)
    }
}
