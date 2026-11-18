//
//  NavigationController.swift
//  Midoku (iOS)
//
//  Created by axiel7 on 11/02/2024.
//

import UIKit

/// A screen that draws its own web-style top bar (back button and actions) instead of the navigation bar.
protocol MDBarlessScreen: UIViewController {}

class NavigationController: UINavigationController, UINavigationControllerDelegate {
    override var childForStatusBarHidden: UIViewController? {
        topViewController is ReaderViewController ? topViewController : super.childForStatusBarHidden
    }
    override var childForStatusBarStyle: UIViewController? {
        topViewController is ReaderViewController ? topViewController : super.childForStatusBarStyle
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        interactivePopGestureRecognizer?.isEnabled = true
        if #available(iOS 26.0, *) { interactiveContentPopGestureRecognizer?.isEnabled = true }
        // Swipe back keeps working on screens with a hidden bar or back button.
        MDSwipeBackDelegate.install(on: self)
    }
    /// Tab roots that draw the web page header themselves hide the navigation bar; pushed screens show it
    /// unless they adopt `MDBarlessScreen`.
    var hidesBarAtRoot = false {
        didSet { if isViewLoaded, let top = topViewController { setNavigationBarHidden(wantsBarHidden(top), animated: false) } }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let top = topViewController { setNavigationBarHidden(wantsBarHidden(top), animated: false) }
    }

    private func wantsBarHidden(_ viewController: UIViewController) -> Bool {
        if viewController is ReaderViewController { return isNavigationBarHidden }
        return viewController is MDBarlessScreen || (hidesBarAtRoot && viewController === viewControllers.first)
    }

    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        setNavigationBarHidden(wantsBarHidden(viewController), animated: animated)
        Self.flattenBarItems(of: viewController.navigationItem)
        // A cancelled swipe back stays on the screen it started from.
        transitionCoordinator?.notifyWhenInteractionChanges { [weak self] context in
            guard context.isCancelled, let self, let top = self.topViewController else { return }
            self.setNavigationBarHidden(self.wantsBarHidden(top), animated: true)
        }
    }

    // Only tab roots use large titles (the web's big page headings); pushed screens keep inline titles.
    override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        if !viewControllers.isEmpty, viewController.navigationItem.largeTitleDisplayMode == .automatic {
            viewController.navigationItem.largeTitleDisplayMode = .never
        }
        // The back button comes from the screen underneath: a plain chevron with no glass capsule.
        if let top = topViewController, top.navigationItem.backBarButtonItem == nil {
            let back = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)
            back.hidesSharedBackground = true
            top.navigationItem.backBarButtonItem = back
            top.navigationItem.backButtonDisplayMode = .minimal
        }
        super.pushViewController(viewController, animated: animated)
    }

    /// Midoku Web bars are flat: no shared glass background behind bar buttons.
    static func flattenBarItems(of item: UINavigationItem) {
        for button in (item.leftBarButtonItems ?? []) + (item.rightBarButtonItems ?? []) {
            button.hidesSharedBackground = true
        }
        item.backBarButtonItem?.hidesSharedBackground = true
    }

    // This is a workaround to fix an iOS bug that occurs when mixing UIKit with SwiftUI,
    // that causes the current TabBarItem title to be lost when navigating inside SwiftUI views.
    // See: https://stackoverflow.com/questions/62662313/uitabbar-containing-swiftui-view
    private var storedTabBarItem: UITabBarItem?
    override var tabBarItem: UITabBarItem! {
        get { storedTabBarItem ?? super.tabBarItem }
        set { storedTabBarItem = newValue }
    }

    // fix for incognito mode banner status bar text being the wrong color sometimes on ios 26+
    override var preferredStatusBarStyle: UIStatusBarStyle {
        if AppSettings.general.incognitoMode.get() {
            traitCollection.userInterfaceStyle == .light ? .darkContent : .lightContent
        } else {
            .default
        }
    }
}
