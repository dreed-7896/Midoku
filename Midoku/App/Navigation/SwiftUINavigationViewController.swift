//
//  SwiftUINavigationViewController.swift
//  Midoku (iOS)
//
//  Created by Skitty on 1/6/23.
//

import SwiftUI

class SwiftUINavigationViewController<Content: View>: UINavigationController {
    let path = NavigationCoordinator(rootViewController: nil)

    private var hidesBar = false

    /// `hidesNavigationBar`: every screen draws the web page header itself (`mdFlowPage`).
    init(rootView: Content, addDismissButton: Bool = true, hidesNavigationBar: Bool = false) {
        let view = ModelWrapper(rootView: rootView, path: path, addDismissButton: addDismissButton && !hidesNavigationBar)
        super.init(rootViewController: UIHostingController(rootView: view.midokuStyle()))
        path.rootViewController = self
        hidesBar = hidesNavigationBar
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if hidesBar {
            setNavigationBarHidden(true, animated: false)
            MDSwipeBackDelegate.install(on: self)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct ModelWrapper<Content: View>: View {
    let rootView: Content
    let path: NavigationCoordinator
    let addDismissButton: Bool

    var body: some View {
        let view = rootView.environmentObject(path)
        if addDismissButton {
            view
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        CloseButton {
                            path.dismiss()
                        }
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
        } else {
            view
        }
    }
}
