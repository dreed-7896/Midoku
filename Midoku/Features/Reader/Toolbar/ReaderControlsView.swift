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
    let bookmarkButton = UIButton(type: .system)
    let settingsButton = UIButton(type: .system)
    let autoScrollButton = UIButton(type: .system)
    let translationButton = UIButton(type: .system)

    init() {
        super.init(effect: nil)
        backgroundColor = MDColor.bg.withAlphaComponent(0.94)
        clipsToBounds = false
        for (button, symbol, label) in [
            (chaptersButton, "list.bullet", "Chapters"),
            (panelsButton, "square.grid.2x2", "View pages"),
            (bookmarkButton, "bookmark", "Bookmark this page"),
            (autoScrollButton, "play.fill", "Start auto scroll"),
            (translationButton, "character.bubble", "Enable translation"),
            (settingsButton, "textformat.size", "Reader settings")
        ] {
            ReaderBarButton.style(button, symbol: symbol)
            button.accessibilityLabel = label
        }
        let actions = UIStackView(arrangedSubviews: [chaptersButton, panelsButton, bookmarkButton, autoScrollButton, translationButton, settingsButton])
        actions.axis = .horizontal
        actions.alignment = .center
        actions.distribution = .equalSpacing

        let border = UIView()
        border.backgroundColor = MDColor.line
        border.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(border)

        let stack = UIStackView(arrangedSubviews: [toolbar, actions])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        let readable = stack.widthAnchor.constraint(lessThanOrEqualToConstant: 600)
        let fill = stack.widthAnchor.constraint(equalTo: contentView.widthAnchor, constant: -24)
        fill.priority = .defaultHigh
        NSLayoutConstraint.activate([
            border.topAnchor.constraint(equalTo: contentView.topAnchor),
            border.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            border.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            border.heightAnchor.constraint(equalToConstant: 1),
            readable, fill,
            stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -10),
            toolbar.heightAnchor.constraint(equalToConstant: 66)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setBookmarked(_ bookmarked: Bool) {
        bookmarkButton.configuration?.image = UIImage(systemName: bookmarked ? "bookmark.fill" : "bookmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))
        bookmarkButton.configuration?.baseForegroundColor = bookmarked ? MDColor.accent : MDColor.text
        bookmarkButton.accessibilityLabel = bookmarked ? "Remove page bookmark" : "Bookmark this page"
    }
}

/// Floating top bar with the back button, the current chapter and the webview action.
final class ReaderTopBarView: UIVisualEffectView {
    let closeButton = UIButton(type: .system)
    let webButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    init() {
        super.init(effect: nil)
        backgroundColor = MDColor.bg.withAlphaComponent(0.94)
        clipsToBounds = false

        ReaderBarButton.style(closeButton, symbol: "chevron.backward")
        closeButton.accessibilityLabel = "Back"
        ReaderBarButton.style(webButton, symbol: "safari")
        webButton.accessibilityLabel = "Open in webview"

        // web `.reader__entry` (mono, uppercase, muted) over `.reader__chapter` (15pt bold)
        subtitleLabel.font = MDFont.mono(11, .semibold) ?? .monospacedSystemFont(ofSize: 11, weight: .semibold)
        subtitleLabel.textColor = MDColor.text3
        subtitleLabel.textAlignment = .left
        titleLabel.font = MDFont.ui(15, .bold) ?? .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = MDColor.text
        titleLabel.textAlignment = .left
        let titles = UIStackView(arrangedSubviews: [subtitleLabel, titleLabel])
        titles.axis = .vertical
        titles.alignment = .fill
        titles.spacing = 2
        titles.isAccessibilityElement = true
        titles.accessibilityTraits = .header
        titles.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let border = UIView()
        border.backgroundColor = MDColor.line
        border.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(border)

        let stack = UIStackView(arrangedSubviews: [closeButton, titles, webButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            border.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            border.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            border.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            border.heightAnchor.constraint(equalToConstant: 1),
            stack.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setTitle(_ title: String, subtitle: String?) {
        titleLabel.text = title
        subtitleLabel.text = subtitle?.uppercased()
        subtitleLabel.isHidden = subtitle?.isEmpty ?? true
        titleLabel.superview?.accessibilityLabel = [title, subtitle].compactMap { $0 }.joined(separator: ", ")
    }
}

/// `.icon-btn--glass`: 44pt square, dark translucent fill, faint white hairline.
enum ReaderBarButton {
    static func style(_ button: UIButton, symbol: String) {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold))
        configuration.baseForegroundColor = MDColor.text
        configuration.contentInsets = .zero
        configuration.background.backgroundColor = MDColor.bg.withAlphaComponent(0.42)
        configuration.background.strokeColor = UIColor.white.withAlphaComponent(0.12)
        configuration.background.strokeWidth = 1
        configuration.background.cornerRadius = 0
        button.configuration = configuration
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 44),
            button.heightAnchor.constraint(equalToConstant: 44)
        ])
    }
}
