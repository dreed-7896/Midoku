//
//  MDTabBar.swift
//  Midoku
//
//  The Midoku Web bottom navigation: flat, square, blurred dark bar with a hairline on top;
//  icon over label, the active tab in the accent with a short accent rule along the top edge.
//

import UIKit

final class MDTabBar: UIView {
    struct Item {
        let title: String
        let image: String
    }

    static let barHeight: CGFloat = 54

    /// Space below the items: less than the full home-indicator inset, like the web dock.
    static func bottomPadding(safeBottom: CGFloat) -> CGFloat {
        8 + safeBottom * 0.45
    }

    static func height(safeBottom: CGFloat) -> CGFloat {
        barHeight + bottomPadding(safeBottom: safeBottom)
    }

    var onSelect: ((Int) -> Void)?

    var selectedIndex = 0 {
        didSet { updateSelection() }
    }

    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let tint = UIView()
    private let hairline = UIView()
    private let stack = UIStackView()
    private var buttons: [ItemButton] = []
    private var stackBottom: NSLayoutConstraint?

    init(items: [Item]) {
        super.init(frame: .zero)
        overrideUserInterfaceStyle = .dark

        blur.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blur)
        tint.backgroundColor = MDColor.tabBar
        tint.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tint)
        hairline.backgroundColor = MDColor.line
        hairline.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hairline)

        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        for (index, item) in items.enumerated() {
            let button = ItemButton(item: item)
            button.addAction(UIAction { [weak self] _ in self?.onSelect?(index) }, for: .touchUpInside)
            buttons.append(button)
            stack.addArrangedSubview(button)
        }

        let bottom = stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        stackBottom = bottom
        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            tint.leadingAnchor.constraint(equalTo: leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: trailingAnchor),
            tint.topAnchor.constraint(equalTo: topAnchor),
            tint.bottomAnchor.constraint(equalTo: bottomAnchor),
            hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.topAnchor.constraint(equalTo: topAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1),
            stack.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.heightAnchor.constraint(equalToConstant: Self.barHeight),
            bottom
        ])
        bottom.priority = .defaultHigh
        updateSelection()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setBadge(_ value: String?, at index: Int) {
        guard buttons.indices.contains(index) else { return }
        buttons[index].badge = value
    }

    private func updateSelection() {
        for (index, button) in buttons.enumerated() {
            button.isActive = index == selectedIndex
        }
    }
}

private final class ItemButton: UIControl {
    private let icon = UIImageView()
    private let label = UILabel()
    private let rule = UIView()
    private let badgeLabel = PaddedLabel()

    var isActive = false {
        didSet { update() }
    }

    var badge: String? {
        didSet {
            badgeLabel.text = badge
            badgeLabel.isHidden = badge == nil
        }
    }

    init(item: MDTabBar.Item) {
        super.init(frame: .zero)
        accessibilityLabel = item.title
        accessibilityTraits = .button

        icon.image = UIImage(named: item.image)?.withRenderingMode(.alwaysTemplate)
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.isUserInteractionEnabled = false
        addSubview(icon)

        label.text = item.title
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isUserInteractionEnabled = false
        addSubview(label)

        rule.backgroundColor = MDColor.accent
        rule.translatesAutoresizingMaskIntoConstraints = false
        rule.isUserInteractionEnabled = false
        addSubview(rule)

        badgeLabel.backgroundColor = MDColor.accent
        badgeLabel.textColor = MDColor.onAccent
        badgeLabel.font = MDFont.mono(11, .bold) ?? .monospacedSystemFont(ofSize: 11, weight: .bold)
        badgeLabel.textAlignment = .center
        badgeLabel.isHidden = true
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badgeLabel)

        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),
            icon.bottomAnchor.constraint(equalTo: centerYAnchor, constant: 3),
            label.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 3),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            rule.topAnchor.constraint(equalTo: topAnchor),
            rule.heightAnchor.constraint(equalToConstant: 2),
            rule.centerXAnchor.constraint(equalTo: centerXAnchor),
            rule.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.56),
            badgeLabel.topAnchor.constraint(equalTo: icon.topAnchor, constant: -6),
            badgeLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: -8),
            badgeLabel.heightAnchor.constraint(equalToConstant: 18),
            badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 18)
        ])
        update()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }

    private func update() {
        let color = isActive ? MDColor.accent : MDColor.text3
        icon.tintColor = color
        label.textColor = color
        label.font = MDFont.ui(11, isActive ? .semibold : .medium) ?? .systemFont(ofSize: 11, weight: isActive ? .semibold : .medium)
        rule.isHidden = !isActive
        if isActive { accessibilityTraits.insert(.selected) } else { accessibilityTraits.remove(.selected) }
    }
}

private final class PaddedLabel: UILabel {
    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + 8, height: size.height)
    }
}
