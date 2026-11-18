import SwiftUI

struct UpdatesHistoryView: View {
    enum Page: String, CaseIterable {
        case updates = "Updates"
        case history = "History"
    }

    @State private var page: Page
    @EnvironmentObject private var path: NavigationCoordinator
    var onBack: (() -> Void)?

    init(page: Page = .updates, onBack: (() -> Void)? = nil) {
        _page = State(initialValue: page)
        self.onBack = onBack
    }

    private var weekday: String {
        Date.now.formatted(.dateTime.weekday(.wide))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let onBack {
                MDIconButton(systemImage: "chevron.left", label: "Back", action: onBack)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
            }
            MDPageHeader(kicker: weekday, title: page.rawValue) {
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
        .navigationTitle("Updates")
    }

    /// This screen is hosted in a UIKit navigation controller, where a SwiftUI sheet
    /// triggered from a bridged toolbar item can fail to present. Present it directly.
    private func showFollowedTitles() {
        guard let presenter = path.rootViewController, presenter.presentedViewController == nil else { return }
        presenter.present(UIHostingController(rootView: MCFollowedTitlesView()), animated: true)
    }
}

/// Updates and History pushed from Home, with the web's back square instead of a navigation bar.
final class UpdatesHistoryController: UIHostingController<AnyView>, MDBarlessScreen {
    init(page: UpdatesHistoryView.Page) {
        let path = NavigationCoordinator(rootViewController: nil)
        super.init(rootView: AnyView(EmptyView()))
        path.rootViewController = self
        rootView = AnyView(UpdatesHistoryView(page: page, onBack: { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }).environmentObject(path).midokuStyle())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
