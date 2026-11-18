import SwiftUI

struct UpdatesHistoryView: View {
    private enum Page: String, CaseIterable {
        case updates = "Updates"
        case history = "History"
    }

    @State private var page = Page.updates
    @EnvironmentObject private var path: NavigationCoordinator

    private var weekday: String {
        Date.now.formatted(.dateTime.weekday(.wide))
    }

    var body: some View {
        VStack(spacing: 0) {
            MDPageHeader(kicker: weekday, title: "Feed") {
                if page == .updates {
                    MDIconButton(systemImage: "bell", label: "Manage titles getting new chapters", action: showFollowedTitles)
                }
            }
            HStack(spacing: 8) {
                ForEach(Page.allCases, id: \.self) { item in
                    Button { page = item } label: { MDChip(title: item.rawValue, active: page == item) }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(page == item ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            if page == .updates {
                MangaUpdatesView()
            } else {
                HistoryView()
            }
        }
        .background(Color.mdBg)
        .navigationTitle("Feed")
    }

    /// This screen is hosted in a UIKit navigation controller, where a SwiftUI sheet
    /// triggered from a bridged toolbar item can fail to present. Present it directly.
    private func showFollowedTitles() {
        guard let presenter = path.rootViewController, presenter.presentedViewController == nil else { return }
        presenter.present(UIHostingController(rootView: MCFollowedTitlesView()), animated: true)
    }
}
