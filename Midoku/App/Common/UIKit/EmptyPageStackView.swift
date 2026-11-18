//
//  EmptyPageStackView.swift
//  Midoku (iOS)
//
//  Created by Skitty on 8/12/22.
//

import UIKit

/// Empty page message in Midoku Web's look (`<Empty>` card). Keeps the old stack view API.
class EmptyPageStackView: UIStackView {
    var imageSystemName: String? {
        didSet { refresh() }
    }

    var title: String? {
        didSet { refresh() }
    }

    var text: String? {
        didSet { refresh() }
    }

    var buttonText: String? {
        didSet { refresh() }
    }

    var showsButton = false {
        didSet { refresh() }
    }

    private let card = MDStateCardView()
    private var widthConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        axis = .vertical
        alignment = .fill
        addArrangedSubview(card)
        refresh()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        widthConstraint?.isActive = false
        guard let superview else { return }
        let width = widthAnchor.constraint(equalTo: superview.widthAnchor, constant: -32)
        width.priority = .defaultHigh
        let cap = widthAnchor.constraint(lessThanOrEqualToConstant: 560)
        NSLayoutConstraint.activate([width, cap])
        widthConstraint = width
    }

    private func refresh() {
        card.set(systemImage: imageSystemName ?? "info.circle", title: title ?? "", detail: text)
        card.setAction(showsButton ? buttonText : nil)
    }

    func addButtonTarget(_ target: Any?, action: Selector, for event: UIControl.Event = .touchUpInside) {
        card.actionButton.addTarget(target, action: action, for: event)
    }
}
