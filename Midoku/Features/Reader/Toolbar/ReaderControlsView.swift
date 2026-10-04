import UIKit

/// A compact floating panel shared by every image and text reading mode.
final class ReaderControlsView: UIVisualEffectView {
    let toolbar = ReaderToolbarView()
    let titleLabel = UILabel()
    let closeButton = UIButton(type: .system)
    let chaptersButton = UIButton(type: .system)
    let settingsButton = UIButton(type: .system)
    let webButton = UIButton(type: .system)
    let autoScrollSwitch = UISwitch()

    init() {
        super.init(effect: UIBlurEffect(style: .systemThinMaterial))
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        clipsToBounds = true
        titleLabel.font = .preferredFont(forTextStyle: .subheadline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textAlignment = .left
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.textColor = .label
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let header = UIStackView(arrangedSubviews: [closeButton, titleLabel])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 4
        header.setCustomSpacing(8, after: closeButton)
        header.setCustomSpacing(8, after: titleLabel)
        for (button, symbol, label) in [
            (closeButton, "xmark", "Close reader"),
            (webButton, "safari", "Webview"),
            (chaptersButton, "list.bullet", "Chapters"),
            (settingsButton, "slider.horizontal.3", "Settings")
        ] {
            var configuration = UIButton.Configuration.plain()
            configuration.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold))
            configuration.baseForegroundColor = .label
            configuration.contentInsets = .zero
            if button === closeButton {
                configuration.background.backgroundColor = .tertiarySystemFill
                configuration.background.cornerRadius = 12
            } else {
                configuration.title = label
                configuration.imagePlacement = .top
                configuration.imagePadding = 5
                configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                    var attributes = attributes
                    attributes.font = .systemFont(ofSize: 11, weight: .medium)
                    return attributes
                }
            }
            button.configuration = configuration
            button.accessibilityLabel = label
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            if button === closeButton {
                button.widthAnchor.constraint(equalToConstant: 44).isActive = true
            }
        }
        autoScrollSwitch.accessibilityLabel = "AutoScroll"
        let autoScrollLabel = UILabel()
        autoScrollLabel.text = "AutoScroll"
        autoScrollLabel.font = .systemFont(ofSize: 11, weight: .medium)
        autoScrollLabel.textColor = .label
        let autoScrollControl = UIStackView(arrangedSubviews: [autoScrollSwitch, autoScrollLabel])
        autoScrollControl.axis = .vertical
        autoScrollControl.alignment = .center
        autoScrollControl.spacing = 4
        let actions = UIStackView(arrangedSubviews: [webButton, chaptersButton, autoScrollControl, settingsButton])
        actions.axis = .horizontal
        actions.alignment = .center
        actions.distribution = .fillEqually
        actions.spacing = 4
        let stack = UIStackView(arrangedSubviews: [header, toolbar, actions])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            toolbar.heightAnchor.constraint(equalToConstant: 58)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
