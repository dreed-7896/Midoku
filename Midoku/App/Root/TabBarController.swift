//
//  TabBarController.swift
//  Midoku
//
//  Created by Skitty on 7/26/25.
//

import Combine
import LocalAuthentication
import SwiftUI
import SwiftUIIntrospect

class TabBarController: UITabBarController {
    private var originalFrame: CGRect = .zero
    private var shrunkFrame: CGRect = .zero
    private var cancellables: [AnyCancellable] = []

    private var settingsPath: NavigationCoordinator?
    private var previousSelectedIndex: Int?

    private weak var historyNavigationController: UINavigationController?
    private weak var searchNavigationController: UINavigationController?

    private let searchController = SearchViewController()
    private var appLockOverlay: UIView?
    private var appLockButton: UIButton?
    private var appSwitcherBlurOverlay: UIVisualEffectView?
    private var appBackgroundedAt: Date?
    private var hasAuthenticatedAppLock = false
    private var unlockingApp = false

    private lazy var libraryProgressView = CircularProgressView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))

    private lazy var libraryRefreshAccessory: UIView = {
        let view = UIView()

        let label = UILabel()
        label.text = NSLocalizedString("REFRESHING_LIBRARY")
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        libraryProgressView.radius = 12
        libraryProgressView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(libraryProgressView)

        if #unavailable(iOS 26) {
            // add styling for older versions without the bottom accessory view
            let backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
            backgroundView.layer.cornerRadius = 48 / 2
            backgroundView.layer.borderColor = UIColor.quaternarySystemFill.cgColor
            backgroundView.layer.borderWidth = 1
            backgroundView.clipsToBounds = true
            backgroundView.translatesAutoresizingMaskIntoConstraints = false
            view.insertSubview(backgroundView, at: 0)

            NSLayoutConstraint.activate([
                backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
                backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: libraryProgressView.leadingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.heightAnchor.constraint(equalToConstant: 48),

            libraryProgressView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            libraryProgressView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            libraryProgressView.widthAnchor.constraint(equalToConstant: 20),
            libraryProgressView.heightAnchor.constraint(equalToConstant: 20)
        ])

        return view
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        delegate = self

        let libraryViewController = UIHostingController(rootView: MCCollectionRootView())
        let browseViewController = NavigationController(rootViewController: BrowseViewController())
        let searchViewController = NavigationController(rootViewController: searchController)
        searchNavigationController = searchViewController

        let historyPath = NavigationCoordinator(rootViewController: nil)
        let historyHostingController = UIHostingController(rootView: HistoryView()
            .environmentObject(historyPath))
        historyPath.rootViewController = historyHostingController
        let historyViewController = NavigationController(rootViewController: historyHostingController)
        historyNavigationController = historyViewController

        let settingsPath = NavigationCoordinator(rootViewController: nil)
        let settingsViewController: UIViewController
        if #available(iOS 26.0, *), UIDevice.current.userInterfaceIdiom != .pad {
            settingsViewController = UIHostingController(
                rootView: NavigationStack {
                    SettingsView()
                        .environmentObject(settingsPath)
                }.introspect(.navigationStack, on: .iOS(.v26, .v27)) { entity in
                    settingsPath.rootViewController = entity
                }
            )
        } else {
            // this breaks the zoom transitions from the toolbar buttons in the backups setting page on ios 18 / ipads
            let hosting = UIHostingController(rootView: SettingsView().environmentObject(settingsPath))
            let entity = NavigationController(rootViewController: hosting)
            entity.navigationBar.prefersLargeTitles = false
            settingsPath.rootViewController = entity
            settingsViewController = entity
        }
        self.settingsPath = settingsPath

        // The collection hosts its native SwiftUI navigation stack.
        browseViewController.navigationBar.prefersLargeTitles = false
        historyViewController.navigationBar.prefersLargeTitles = false
        searchViewController.navigationBar.prefersLargeTitles = false

        if #available(iOS 26.0, *) {
            let searchTab = UISearchTab { _ in
                searchViewController
            }
            searchTab.automaticallyActivatesSearch = true
            let fixedTabs = [
                UITab(
                    title: NSLocalizedString("LIBRARY"),
                    image: UIImage(systemName: "books.vertical.fill"),
                    identifier: "0"
                ) { _ in
                    libraryViewController
                },
                UITab(
                    title: NSLocalizedString("BROWSE"),
                    image: UIImage(systemName: "globe"),
                    identifier: "1"
                ) { _ in
                    browseViewController
                },
                UITab(
                    title: NSLocalizedString("HISTORY"),
                    image: UIImage(systemName: "clock.fill"),
                    identifier: "2"
                ) { _ in
                    historyViewController
                },
                UITab(
                    title: NSLocalizedString("SETTINGS"),
                    image: UIImage(systemName: "gear"),
                    identifier: "3"
                ) { _ in
                    settingsViewController
                }
            ]
            fixedTabs.forEach {
                $0.allowsHiding = false
                $0.preferredPlacement = .fixed
            }
            tabs = fixedTabs + [searchTab]
        } else {
            libraryViewController.tabBarItem = UITabBarItem(
                title: NSLocalizedString("LIBRARY"),
                image: UIImage(systemName: "books.vertical.fill"),
                tag: 0
            )
            browseViewController.tabBarItem = UITabBarItem(
                title: NSLocalizedString("BROWSE"),
                image: UIImage(systemName: "globe"),
                tag: 1
            )
            historyViewController.tabBarItem = UITabBarItem(
                tabBarSystemItem: .history,
                tag: 2
            )
            searchViewController.tabBarItem = UITabBarItem(
                tabBarSystemItem: .search,
                tag: 3
            )
            settingsViewController.tabBarItem = UITabBarItem(
                title: NSLocalizedString("SETTINGS"),
                image: UIImage(systemName: "gear"),
                tag: 4
            )
            viewControllers = [
                libraryViewController,
                browseViewController,
                historyViewController,
                searchViewController,
                settingsViewController
            ]
        }

        applyOpeningTab()

        let updateCount = AppSettings.browse.updateCount.get()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--history-preview") { selectedIndex = 2 }
        if ProcessInfo.processInfo.arguments.contains("--appearance-preview") { selectedIndex = 3 }
        #endif
        browseViewController.tabBarItem.badgeValue = updateCount > 0 ? String(updateCount) : nil

        NotificationCenter.default.publisher(for: .init(AppSettings.general.incognitoMode.key))
            .sink { [weak self] _ in
                self?.updateFrame(animated: true)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                self?.handleAppWillResignActive()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                guard AppSettings.general.appLock.get() else { return }
                self?.appBackgroundedAt = Date()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in self?.prepareAppLockForForeground() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.hideAppSwitcherBlur()
                self?.unlockAppIfNeeded()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .init(AppSettings.general.appLock.key))
            .sink { [weak self] _ in
                if AppSettings.general.appLock.get() {
                    self?.hasAuthenticatedAppLock = false
                    self?.showAppLock()
                    self?.unlockAppIfNeeded()
                } else {
                    self?.hasAuthenticatedAppLock = false
                    self?.appBackgroundedAt = nil
                    self?.hideAppLock()
                }
            }
            .store(in: &cancellables)

    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if AppSettings.general.appLock.get(), !hasAuthenticatedAppLock {
            showAppLock()
            unlockAppIfNeeded()
        }
    }

    func updateFrame(animated: Bool = false) {
        if originalFrame == .zero {
            let bannerHeight = (UIApplication.shared.connectedScenes.first?.delegate as? SceneDelegate)?.totalBannerHeight ?? 0
            originalFrame = view.frame
            shrunkFrame = .init(
                x: originalFrame.origin.x,
                y: originalFrame.origin.y + bannerHeight,
                width: originalFrame.width,
                height: originalFrame.height - bannerHeight
            )
        }
        func commit() {
            if AppSettings.general.incognitoMode.get() {
                view.frame = shrunkFrame
            } else {
                view.frame = originalFrame
            }
        }
        if animated {
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                commit()
            }
        } else {
            commit()
        }
    }
}

private extension TabBarController {
    func handleAppWillResignActive() {
        guard AppSettings.general.appLock.get() else { return }
        if AppSettings.general.appLockDelay.get().seconds == 0 {
            hasAuthenticatedAppLock = false
            showAppLock()
        }
        if AppSettings.general.blurAppSwitcher.get() { showAppSwitcherBlur() }
    }

    func prepareAppLockForForeground() {
        defer { appBackgroundedAt = nil }
        guard AppSettings.general.appLock.get(), hasAuthenticatedAppLock else {
            if AppSettings.general.appLock.get() { showAppLock() }
            return
        }
        guard let appBackgroundedAt else { return }
        let delay = AppSettings.general.appLockDelay.get().seconds
        if Date().timeIntervalSince(appBackgroundedAt) >= delay {
            hasAuthenticatedAppLock = false
            showAppLock()
        }
    }

    func showAppSwitcherBlur() {
        guard appSwitcherBlurOverlay == nil,
              let container = view.window ?? UIApplication.shared.firstKeyWindow else { return }
        let overlay = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.contentView.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.3)
        container.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: container.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        appSwitcherBlurOverlay = overlay
    }

    func hideAppSwitcherBlur() {
        appSwitcherBlurOverlay?.removeFromSuperview()
        appSwitcherBlurOverlay = nil
    }

    func showAppLock() {
        guard appLockOverlay == nil, let container = view.window ?? UIApplication.shared.firstKeyWindow else { return }

        let overlay = UIView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.backgroundColor = .systemBackground
        overlay.accessibilityViewIsModal = true

        let symbol = UIImage.SymbolConfiguration(pointSize: 54, weight: .medium)
        let icon = UIImageView(image: UIImage(systemName: "lock.fill", withConfiguration: symbol))
        icon.tintColor = .secondaryLabel
        icon.contentMode = .scaleAspectFit
        icon.isAccessibilityElement = false

        let title = UILabel()
        title.text = "Midoku is locked"
        title.font = .preferredFont(forTextStyle: .title2)
        title.adjustsFontForContentSizeCategory = true
        title.textAlignment = .center

        let detail = UILabel()
        detail.text = "Authenticate to continue."
        detail.font = .preferredFont(forTextStyle: .subheadline)
        detail.textColor = .secondaryLabel
        detail.adjustsFontForContentSizeCategory = true
        detail.textAlignment = .center

        var configuration = UIButton.Configuration.filled()
        configuration.title = "Unlock Midoku"
        configuration.image = UIImage(systemName: "faceid")
        configuration.imagePadding = 8
        configuration.cornerStyle = .large
        let button = UIButton(configuration: configuration)
        button.addAction(UIAction { [weak self] _ in
            Task { @MainActor in self?.unlockAppIfNeeded() }
        }, for: .touchUpInside)
        button.accessibilityHint = "Uses Face ID, Touch ID, or your device passcode"
        appLockButton = button

        let stack = UIStackView(arrangedSubviews: [icon, title, detail, button])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 12
        stack.setCustomSpacing(22, after: detail)

        overlay.addSubview(stack)
        container.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: container.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: overlay.centerYAnchor, constant: -24),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: overlay.leadingAnchor, constant: 36),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: overlay.trailingAnchor, constant: -36),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 340),
            icon.heightAnchor.constraint(equalToConstant: 72),
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 50)
        ])
        appLockOverlay = overlay
    }

    func hideAppLock() {
        appLockOverlay?.removeFromSuperview()
        appLockOverlay = nil
        appLockButton = nil
        unlockingApp = false
    }

    func unlockAppIfNeeded() {
        guard AppSettings.general.appLock.get(), appLockOverlay != nil, !unlockingApp else { return }
        unlockingApp = true
        appLockButton?.isEnabled = false
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.unlockingApp = false
                self.appLockButton?.isEnabled = true
            }
            do {
                let success = try await LAContext().evaluatePolicy(
                    .defaultPolicy,
                    localizedReason: "Unlock Midoku"
                )
                if success {
                    self.hasAuthenticatedAppLock = true
                    self.hideAppLock()
                }
            } catch {
                // Keep the lock screen visible so the user can retry.
            }
        }
    }
}

extension TabBarController {
    func search(for query: String) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Defer the tab change until the originating SwiftUI gesture has finished.
            await Task.yield()
            if #available(iOS 26.0, *) {
                self.selectedTab = self.tabs.last
            } else {
                self.selectedViewController = self.searchNavigationController
            }
            await Task.yield()
            self.searchNavigationController?.popToRootViewController(animated: false)
            self.searchController.search(for: query)
        }
    }

    private func applyOpeningTab() {
        let openingTab = AppSettings.general.openingTab.get()
        if #available(iOS 26.0, *) {
            switch openingTab {
            case .search:
                selectedTab = tabs.last
            case .library:
                selectedTab = tabs.first { $0.identifier == "0" }
            case .browse:
                selectedTab = tabs.first { $0.identifier == "1" }
            case .history:
                selectedTab = tabs.first { $0.identifier == "2" }
            case .settings:
                selectedTab = tabs.first { $0.identifier == "3" }
            }
        } else {
            selectedIndex = switch openingTab {
            case .library: 0
            case .browse: 1
            case .history: 2
            case .search: 3
            case .settings: 4
            }
        }
    }

    func showLibraryRefreshView() {
        libraryProgressView.setProgress(value: 0, withAnimation: false)

        if #available(iOS 26.0, *) {
            setBottomAccessory(.init(contentView: libraryRefreshAccessory), animated: true)
        } else {
            libraryRefreshAccessory.layer.opacity = 0
            view.insertSubview(libraryRefreshAccessory, belowSubview: tabBar)
            UIView.animate(withDuration: 0.5) {
                self.libraryRefreshAccessory.layer.opacity = 1
            }
        }
    }

    func setLibraryRefreshProgress(_ progress: Float) {
        libraryProgressView.setProgress(value: progress, withAnimation: true)
    }

    func hideAccessoryView() {
        if #available(iOS 26.0, *) {
            setBottomAccessory(nil, animated: true)
        } else {
            UIView.animate(withDuration: 0.5) {
                self.libraryRefreshAccessory.layer.opacity = 0
            } completion: { _ in
                self.libraryRefreshAccessory.removeFromSuperview()
            }
        }
    }

    override func viewDidLayoutSubviews() {
        if #unavailable(iOS 26.0) {
            let height: CGFloat = 48
            let padding: CGFloat = 16

            libraryRefreshAccessory.frame = CGRect(
                x: tabBar.frame.origin.x + view.safeAreaInsets.left + padding,
                y: tabBar.frame.origin.y - height - padding / 2,
                width: tabBar.frame.width - padding * 2 - view.safeAreaInsets.left - view.safeAreaInsets.right,
                height: height
            )
        }
        updateFrame()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        originalFrame = .init(origin: self.originalFrame.origin, size: size)
        shrunkFrame = self.originalFrame
        coordinator.animate { _ in
            self.view.setNeedsLayout()
        } completion: { _ in
            let bannerHeight = (UIApplication.shared.connectedScenes.first?.delegate as? SceneDelegate)?.totalBannerHeight ?? 0
            self.shrunkFrame = .init(
                x: self.originalFrame.origin.x,
                y: self.originalFrame.origin.y + bannerHeight,
                width: self.originalFrame.width,
                height: self.originalFrame.height - bannerHeight
            )
            self.updateFrame(animated: true)
        }
    }
}

extension TabBarController: UITabBarControllerDelegate {
    @available(iOS 18.0, *)
    func tabBarController(_ tabBarController: UITabBarController, didSelectTab selectedTab: UITab, previousTab: UITab?) {
        checkForSettingsPop()
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        if #unavailable(iOS 18.0) {
            checkForSettingsPop()
        }
    }

    @available(iOS 18.0, *)
    func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
        if tab === tabBarController.selectedTab {
            checkForHistoryReselection()
        }
        return true
    }

    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        if viewController === selectedViewController {
            checkForHistoryReselection()
        }
        return true
    }

    // when the history tab is selected while it's already showing the top of the history list,
    // let the history view know so that it can continue reading the last opened manga
    private func checkForHistoryReselection() {
        guard
            AppSettings.library.continueReadingOnReselect.get(),
            let historyNavigationController,
            selectedViewController === historyNavigationController,
            // if there's anything pushed on top, the default behavior pops back to the history list
            historyNavigationController.viewControllers.count == 1,
            // if the list isn't at the top, the default behavior scrolls it there
            let scrollView = historyNavigationController.topViewController?.view.firstScrollView(),
            scrollView.isScrolledToTop
        else { return }
        NotificationCenter.default.post(name: .historyTabReselected, object: nil)
    }

    private func checkForSettingsPop() {
        let settingsIndex: Int
        if #available(iOS 26.0, *) {
            settingsIndex = 3
        } else {
            settingsIndex = 4
        }
        if selectedIndex == previousSelectedIndex && previousSelectedIndex == settingsIndex {
            settingsPath?.navigationController?.popToRootViewController(animated: true)
        }
        previousSelectedIndex = selectedIndex
    }
}

// MARK: - Keyboard Shortcuts
extension TabBarController {
    override var keyCommands: [UIKeyCommand]? {
        tabBar.items?.enumerated().map { index, item in
            UIKeyCommand(
                title: item.title ?? "Tab \(index + 1)",
                action: #selector(selectTab),
                input: "\(index + 1)",
                modifierFlags: .shiftOrCommand,
                alternates: [],
                attributes: [],
                state: .off
            )
        }
    }

    @objc private func selectTab(sender: UIKeyCommand) {
        guard
            let input = sender.input,
            let newIndex = Int(input),
            newIndex >= 1 && newIndex <= (tabBar.items?.count ?? 0)
        else { return }
        selectedIndex = newIndex - 1
    }

    override var canBecomeFirstResponder: Bool { true }
}
