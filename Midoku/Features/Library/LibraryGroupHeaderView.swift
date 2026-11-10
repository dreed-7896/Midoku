//
//  LibraryGroupHeaderView.swift
//  Midoku
//

import UIKit

/// Title row above one group of titles in a grouped library category. Tapping it collapses the group.
class LibraryGroupHeaderView: UICollectionReusableView {
    static let elementKind = "library-group-header"

    var onTap: (() -> Void)?

    private let titleLabel = UILabel()
    private let countLabel = UILabel()
    private let chevron = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        countLabel.font = .preferredFont(forTextStyle: .subheadline)
        countLabel.adjustsFontForContentSizeCategory = true
        countLabel.textColor = .secondaryLabel

        chevron.image = UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(textStyle: .footnote, scale: .medium))
        chevron.tintColor = .tertiaryLabel
        chevron.contentMode = .scaleAspectFit

        let stack = UIStackView(arrangedSubviews: [titleLabel, countLabel, UIView(), chevron])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 0),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, count: Int, collapsed: Bool) {
        titleLabel.text = title
        countLabel.text = "\(count)"
        chevron.transform = collapsed ? CGAffineTransform(rotationAngle: -.pi / 2) : .identity
        accessibilityLabel = "\(title), \(count)"
        accessibilityValue = collapsed ? "Collapsed" : "Expanded"
    }

    @objc private func tapped() {
        onTap?()
    }
}
