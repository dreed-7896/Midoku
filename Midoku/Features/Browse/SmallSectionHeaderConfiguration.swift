//
//  SmallSectionHeaderConfiguration.swift
//  Midoku (iOS)
//
//  Created by Skitty on 12/31/22.
//

import UIKit

struct SmallSectionHeaderConfiguration: UIContentConfiguration {

    var title: String?

    func makeContentView() -> UIView & UIContentView {
        SmallSectionHeaderContentView(self)
    }

    func updated(for state: UIConfigurationState) -> Self {
        self
    }
}

class SmallSectionHeaderContentView: UIView, UIContentView {

    var configuration: UIContentConfiguration {
        didSet {
            configure()
        }
    }

    let titleLabel = UILabel()

    init(_ configuration: UIContentConfiguration) {
        self.configuration = configuration
        super.init(frame: .zero)

        // `.label`: mono uppercase section label
        titleLabel.font = MDFont.mono(11, .semibold) ?? .monospacedSystemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = MDColor.text3
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16)
        ])

        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure() {
        guard let configuration = configuration as? SmallSectionHeaderConfiguration else { return }
        titleLabel.attributedText = NSAttributedString(
            string: (configuration.title ?? "").uppercased(),
            attributes: [.kern: 1.0]
        )
    }
}
