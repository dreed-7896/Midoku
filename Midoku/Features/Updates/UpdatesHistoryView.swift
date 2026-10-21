import SwiftUI

struct UpdatesHistoryView: View {
    private enum Page: String, CaseIterable {
        case updates = "Updates"
        case history = "History"
    }

    @State private var page = Page.updates
    @EnvironmentObject private var path: NavigationCoordinator

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
                    Button(action: showFollowedTitles) { Image(systemName: "bell.badge") }
                        .accessibilityLabel("Manage titles getting new chapters")
                }
            }
        }
        .navigationTitle("Updates")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// This screen is hosted in a UIKit navigation controller, where a SwiftUI sheet
    /// triggered from a bridged toolbar item can fail to present. Present it directly.
    private func showFollowedTitles() {
        guard let presenter = path.rootViewController, presenter.presentedViewController == nil else { return }
        presenter.present(UIHostingController(rootView: MCFollowedTitlesView()), animated: true)
    }
}
