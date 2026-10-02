import SwiftUI

struct UpdatesHistoryView: View {
    private enum Page: String, CaseIterable {
        case updates = "Updates"
        case history = "History"
    }

    @State private var page = Page.updates
    @State private var showFollowedTitles = false

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
        .toolbar {
            if page == .updates {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showFollowedTitles = true } label: { Image(systemName: "bell.badge") }
                        .accessibilityLabel("Manage titles getting new chapters")
                }
            }
        }
        .sheet(isPresented: $showFollowedTitles) { MCFollowedTitlesView() }
        .navigationTitle("Updates")
        .navigationBarTitleDisplayMode(.inline)
    }
}
