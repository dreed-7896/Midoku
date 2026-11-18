//
//  MDSwipeBack.swift
//  Midoku
//
//  Screens that draw their own web-style top bar hide the navigation bar or its back button, which
//  makes UIKit refuse the swipe back. This delegate keeps the edge swipe and the full-width content
//  swipe working whenever there is a screen to go back to, and forwards everything else to UIKit's
//  own delegate so scroll views and controls keep their usual priority.
//

import UIKit
import ObjectiveC

@MainActor
final class MDSwipeBackDelegate: NSObject, UIGestureRecognizerDelegate {
    private weak var navigation: UINavigationController?
    private weak var original: (any UIGestureRecognizerDelegate)?
    private let fullWidth: Bool

    private init(navigation: UINavigationController, original: (any UIGestureRecognizerDelegate)?, fullWidth: Bool) {
        self.navigation = navigation
        self.original = original
        self.fullWidth = fullWidth
    }

    private static var edgeKey: UInt8 = 0
    private static var contentKey: UInt8 = 0

    /// Installs once per navigation controller; safe to call repeatedly.
    static func install(on navigation: UINavigationController) {
        if let edge = navigation.interactivePopGestureRecognizer, !(edge.delegate is MDSwipeBackDelegate) {
            let delegate = MDSwipeBackDelegate(navigation: navigation, original: edge.delegate, fullWidth: false)
            objc_setAssociatedObject(navigation, &edgeKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            edge.delegate = delegate
            edge.isEnabled = true
        }
        if #available(iOS 26.0, *), let content = navigation.interactiveContentPopGestureRecognizer,
           !(content.delegate is MDSwipeBackDelegate) {
            let delegate = MDSwipeBackDelegate(navigation: navigation, original: content.delegate, fullWidth: true)
            objc_setAssociatedObject(navigation, &contentKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            content.delegate = delegate
        }
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (original?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let original, original.responds(to: aSelector) { return original }
        return super.forwardingTarget(for: aSelector)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let navigation, navigation.viewControllers.count > 1,
              navigation.transitionCoordinator == nil,
              navigation.presentedViewController == nil else { return false }
        if fullWidth, let pan = gestureRecognizer as? UIPanGestureRecognizer {
            // Only a rightward, mostly horizontal drag goes back.
            let velocity = pan.velocity(in: pan.view)
            guard velocity.x > 0, abs(velocity.x) > abs(velocity.y) else { return false }
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if fullWidth {
            var candidate = touch.view
            while let view = candidate {
                if view is UISlider || view is UISwitch { return false }
                // A horizontal list that can still scroll back keeps the drag.
                if let scroll = view as? UIScrollView,
                   scroll.contentSize.width > scroll.bounds.width + 1,
                   scroll.contentOffset.x > -scroll.adjustedContentInset.left + 1 {
                    return false
                }
                candidate = view.superview
            }
        }
        // UIKit's own delegate refuses touches while the bar or back button is hidden, so it isn't asked.
        return true
    }
}
