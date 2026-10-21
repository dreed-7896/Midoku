import UIKit

/// Reader chrome shared by every image and text reading mode: a slim top bar for
/// leaving the reader, and a compact bottom panel for page and reading controls.
final class ReaderControlsView: UIVisualEffectView {
    let toolbar = ReaderToolbarView()
    /// Added to the reader's view separately, since it is pinned to the top edge.
    let topBar = ReaderTopBarView()
    var closeButton: UIButton { topBar.closeButton }
    var webButton: UIButton { topBar.webButton }
    let chaptersButton = UIButton(type: .system)
    let panelsButton = UIButton(type: .system)
    let settingsButton = UIButton(type: .system)
    let autoScrollButton = UIButton(type: .system)
    let translationButton = UIButton(type: .system)

    init() {
        super.init(effect: UIBlurEffect(style: .systemThinMaterial))
        layer.cornerRadius = 24
        layer.cornerCurve = .continuous
        clipsToBounds = true
        for (button, symbol, title, label) in [
            (chaptersButton, "list.bullet", "Chapters", "Chapters"),
            (panelsButton, "square.grid.2x2", "Pages", "View pages"),
            (autoScrollButton, "play.fill", "Auto scroll", "Start auto scroll"),
            (translationButton, "character.bubble", "Translate", "Enable translation"),
            (settingsButton, "textformat.size", "Settings", "Reader settings")
        ] {
            var configuration = UIButton.Configuration.plain()
            configuration.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))
            configuration.imagePlacement = .top
            configuration.imagePadding = 4
            configuration.baseForegroundColor = .label
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0)
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var attributes = attributes
                attributes.font = .systemFont(ofSize: 10, weight: .medium)
                return attributes
            }
            configuration.title = title
            configuration.titleLineBreakMode = .byTruncatingTail
            button.configuration = configuration
            button.accessibilityLabel = label
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        }
        let actions = UIStackView(arrangedSubviews: [chaptersButton, panelsButton, autoScrollButton, translationButton, settingsButton])
        actions.axis = .horizontal
        actions.alignment = .center
        actions.distribution = .fillEqually
        actions.spacing = 4

        let separator = UIView()
        separator.backgroundColor = .separator
        separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true

        let stack = UIStackView(arrangedSubviews: [toolbar, separator, actions])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            toolbar.heightAnchor.constraint(equalToConstant: 66)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Floating top bar with the back button, the current chapter and the webview action.
final class ReaderTopBarView: UIVisualEffectView {
    let closeButton = UIButton(type: .system)
    let webButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    init() {
        super.init(effect: UIBlurEffect(style: .systemThinMaterial))
        layer.cornerRadius = 24
        layer.cornerCurve = .continuous
        clipsToBounds = true

        for (button, symbol, label) in [
            (closeButton, "chevron.backward", "Back"),
            (webButton, "safari", "Open in webview")
        ] {
            var configuration = UIButton.Configuration.plain()
            configuration.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold))
            configuration.baseForegroundColor = .label
            configuration.contentInsets = .zero
            button.configuration = configuration
            button.accessibilityLabel = label
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 44),
                button.heightAnchor.constraint(equalToConstant: 44)
            ])
        }

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textAlignment = .center
        subtitleLabel.font = .systemFont(ofSize: 11, weight: .regular)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        let titles = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        titles.axis = .vertical
        titles.alignment = .fill
        titles.spacing = 1
        titles.isAccessibilityElement = true
        titles.accessibilityTraits = .header
        titles.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [closeButton, titles, webButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setTitle(_ title: String, subtitle: String?) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle?.isEmpty ?? true
        titleLabel.superview?.accessibilityLabel = [title, subtitle].compactMap { $0 }.joined(separator: ", ")
    }
}
