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

    private weak var collectionViewController: UIViewController?
    private weak var historyNavigationController: UINavigationController?
    private weak var searchNavigationController: UINavigationController?

    private let searchController = SearchViewController()
    private var appLockOverlay: UIView?
    private var appLockButton: UIButton?
    private var appSwitcherBlurOverlay: UIVisualEffectView?
    private var appBackgroundedAt: Date?
    private var hasAuthenticatedAppLock = false
    private var unlockingApp = false

    private lazy var customTabBar = MDTabBar(items: [
        .init(title: "Home", image: "MDTabHome"),
        .init(title: NSLocalizedString("LIBRARY"), image: "MDTabLibrary"),
        .init(title: "Search", image: "MDTabSearch"),
        .init(title: "Sources", image: "MDTabSources"),
        .init(title: NSLocalizedString("SETTINGS"), image: "MDTabSettings")
    ])
    private var customTabBarHeight: NSLayoutConstraint?
    private var customTabBarHiddenBySystem = false
    private let visibleReaders = NSHashTable<UIViewController>.weakObjects()
    private static let sourcesTabIndex = 3

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

        // Web banner style: square, raised surface with a hairline border.
        let backgroundView = UIView()
        backgroundView.backgroundColor = MDColor.s2
        backgroundView.layer.borderColor = MDColor.line2.cgColor
        backgroundView.layer.borderWidth = 1
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(backgroundView, at: 0)
        label.font = MDFont.ui(14, .semibold) ?? .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = MDColor.text

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

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

    override var selectedIndex: Int {
        didSet { if isViewLoaded { customTabBar.selectedIndex = selectedIndex } }
    }

    override var selectedViewController: UIViewController? {
        didSet { if isViewLoaded { customTabBar.selectedIndex = selectedIndex } }
    }

    // The system bar always stays hidden; requests to hide or show it move the web bar instead.
    override var isTabBarHidden: Bool {
        get { customTabBarHiddenBySystem }
        set { setTabBarHidden(newValue, animated: false) }
    }

    override func setTabBarHidden(_ hidden: Bool, animated: Bool) {
        customTabBarHiddenBySystem = hidden
        super.setTabBarHidden(true, animated: false)
        refreshCustomTabBar(animated: animated)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        delegate = self

        let libraryViewController = UIHostingController(rootView: MCCollectionRootView().midokuStyle())
        collectionViewController = libraryViewController
        let browseViewController = NavigationController(rootViewController: DiscoverViewController())
        let searchViewController = NavigationController(rootViewController: searchController)
        searchNavigationController = searchViewController

        let historyPath = NavigationCoordinator(rootViewController: nil)
        let historyHostingController = UIHostingController(rootView: UpdatesHistoryView()
            .environmentObject(historyPath)
            .midokuStyle())
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
                        .midokuStyle()
                }.introspect(.navigationStack, on: .iOS(.v26, .v27)) { entity in
                    settingsPath.rootViewController = entity
                }
            )
        } else {
            // this breaks the zoom transitions from the toolbar buttons in the backups setting page on ios 18 / ipads
            let hosting = UIHostingController(rootView: SettingsView().environmentObject(settingsPath).midokuStyle())
            let entity = NavigationController(rootViewController: hosting)
            entity.navigationBar.prefersLargeTitles = true
            settingsPath.rootViewController = entity
            settingsViewController = entity
        }
        self.settingsPath = settingsPath

        // The collection hosts its native SwiftUI navigation stack.
        // Root screens get the web's big display-face page titles.
        browseViewController.navigationBar.prefersLargeTitles = true
        historyViewController.navigationBar.prefersLargeTitles = true
        searchViewController.navigationBar.prefersLargeTitles = true

        // Midoku Web order: Home (updates & history), Library, Search, Sources, Settings.
        historyViewController.tabBarItem = UITabBarItem(title: "Home", image: UIImage(named: "MDTabHome"), tag: 0)
        libraryViewController.tabBarItem = UITabBarItem(
            title: NSLocalizedString("LIBRARY"), image: UIImage(named: "MDTabLibrary"), tag: 1
        )
        searchViewController.tabBarItem = UITabBarItem(title: "Search", image: UIImage(named: "MDTabSearch"), tag: 2)
        browseViewController.tabBarItem = UITabBarItem(title: "Sources", image: UIImage(named: "MDTabSources"), tag: 3)
        settingsViewController.tabBarItem = UITabBarItem(
            title: NSLocalizedString("SETTINGS"), image: UIImage(named: "MDTabSettings"), tag: 4
        )
        viewControllers = [
            historyViewController,
            libraryViewController,
            searchViewController,
            browseViewController,
            settingsViewController
        ]
        installCustomTabBar()

        applyOpeningTab()

        let updateCount = AppSettings.browse.updateCount.get()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--history-preview") { selectedIndex = 0 }
        if ProcessInfo.processInfo.arguments.contains("--appearance-preview") { selectedIndex = 4 }
        #endif
        setSourcesBadge(updateCount)

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
            self.selectedViewController = self.searchNavigationController
            await Task.yield()
            self.searchNavigationController?.popToRootViewController(animated: false)
            self.searchController.search(for: query)
        }
    }

    private func applyOpeningTab() {
        selectedIndex = switch AppSettings.general.openingTab.get() {
        case .history: 0
        case .library: 1
        case .search: 2
        case .browse: 3
        case .settings: 4
        }
    }

    func showLibraryRefreshView() {
        libraryProgressView.setProgress(value: 0, withAnimation: false)

        libraryRefreshAccessory.layer.opacity = 0
        view.insertSubview(libraryRefreshAccessory, belowSubview: customTabBar)
        view.setNeedsLayout()
        UIView.animate(withDuration: 0.5) {
            self.libraryRefreshAccessory.layer.opacity = 1
        }
    }

    func setLibraryRefreshProgress(_ progress: Float) {
        libraryProgressView.setProgress(value: progress, withAnimation: true)
    }

    func hideAccessoryView() {
        UIView.animate(withDuration: 0.5) {
            self.libraryRefreshAccessory.layer.opacity = 0
        } completion: { _ in
            self.libraryRefreshAccessory.removeFromSuperview()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutCustomTabBar()
        let height: CGFloat = 48
        let padding: CGFloat = 16
        libraryRefreshAccessory.frame = CGRect(
            x: view.safeAreaInsets.left + padding,
            y: customTabBar.frame.origin.y - height - padding / 2,
            width: view.bounds.width - padding * 2 - view.safeAreaInsets.left - view.safeAreaInsets.right,
            height: height
        )
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
            checkForLibraryReselection()
        }
        return true
    }

    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        if viewController === selectedViewController {
            checkForHistoryReselection()
            checkForLibraryReselection()
        }
        return true
    }

    private func checkForLibraryReselection() {
        guard selectedViewController === collectionViewController else { return }
        NotificationCenter.default.post(name: .libraryTabReselected, object: nil)
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
        let settingsIndex = 4
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
                action: #selector(selectTab(sender:)),
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
        selectTab(at: newIndex - 1)
    }

    override var canBecomeFirstResponder: Bool { true }
}

// MARK: - Midoku Web tab bar
extension TabBarController {
    private var safeBottom: CGFloat {
        view.window?.safeAreaInsets.bottom ?? (view.safeAreaInsets.bottom - additionalSafeAreaInsets.bottom)
    }

    private var customTabBarVisible: Bool {
        !customTabBarHiddenBySystem && visibleReaders.allObjects.isEmpty
    }

    fileprivate func installCustomTabBar() {
        super.setTabBarHidden(true, animated: false)
        customTabBar.translatesAutoresizingMaskIntoConstraints = false
        customTabBar.onSelect = { [weak self] index in self?.selectTab(at: index) }
        view.addSubview(customTabBar)
        let height = customTabBar.heightAnchor.constraint(equalToConstant: MDTabBar.barHeight)
        customTabBarHeight = height
        NSLayoutConstraint.activate([
            customTabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            customTabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            customTabBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            height
        ])
        customTabBar.selectedIndex = selectedIndex
    }

    fileprivate func layoutCustomTabBar() {
        let height = MDTabBar.height(safeBottom: safeBottom)
        if customTabBarHeight?.constant != height { customTabBarHeight?.constant = height }
        view.bringSubviewToFront(customTabBar)
        let visible = customTabBarVisible
        customTabBar.transform = visible ? .identity : CGAffineTransform(translationX: 0, y: height)
        customTabBar.alpha = visible ? 1 : 0
        let inset = visible ? max(0, height - safeBottom) : 0
        if additionalSafeAreaInsets.bottom != inset {
            additionalSafeAreaInsets.bottom = inset
        }
        customTabBar.selectedIndex = selectedIndex
    }

    private func refreshCustomTabBar(animated: Bool) {
        guard isViewLoaded else { return }
        if animated {
            UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
                self.view.setNeedsLayout()
                self.view.layoutIfNeeded()
            }
        } else {
            view.setNeedsLayout()
            view.layoutIfNeeded()
        }
    }

    func selectTab(at index: Int) {
        guard let controllers = viewControllers, controllers.indices.contains(index) else { return }
        let controller = controllers[index]
        if index == selectedIndex {
            guard tabBarController(self, shouldSelect: controller) else { return }
            if let navigation = controller as? UINavigationController, navigation.viewControllers.count > 1 {
                navigation.popToRootViewController(animated: true)
            } else if let scrollView = controller.view.firstScrollView(), !scrollView.isScrolledToTop {
                scrollView.setContentOffset(
                    CGPoint(x: scrollView.contentOffset.x, y: -scrollView.adjustedContentInset.top),
                    animated: true
                )
            }
            checkForSettingsPop()
            return
        }
        guard tabBarController(self, shouldSelect: controller) else { return }
        selectedIndex = index
        checkForSettingsPop()
    }

    /// Readers cover the whole screen; the bar hides while one is showing inside a tab.
    func readerWillAppear(_ reader: UIViewController) {
        visibleReaders.add(reader)
        refreshCustomTabBar(animated: false)
    }

    func readerDidDisappear(_ reader: UIViewController) {
        visibleReaders.remove(reader)
        refreshCustomTabBar(animated: false)
    }

    func setSourcesBadge(_ count: Int) {
        let value = count > 0 ? String(count) : nil
        if let controllers = viewControllers, controllers.indices.contains(Self.sourcesTabIndex) {
            controllers[Self.sourcesTabIndex].tabBarItem.badgeValue = value
        }
        customTabBar.setBadge(value, at: Self.sourcesTabIndex)
    }
}
