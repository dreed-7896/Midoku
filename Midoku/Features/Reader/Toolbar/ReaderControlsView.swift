import UIKit

/// Reader controls share a single bottom panel, so fullscreen hides every action together.
final class ReaderControlsView: UIVisualEffectView {
    let toolbar = ReaderToolbarView()
    let titleLabel = UILabel()
    let closeButton = UIButton(type: .system)
    let chaptersButton = UIButton(type: .system)
    let settingsButton = UIButton(type: .system)
    let webButton = UIButton(type: .system)

    init() {
        super.init(effect: UIGlassEffect(style: .regular))
        layer.cornerRadius = 28
        clipsToBounds = true
        titleLabel.font = .preferredFont(forTextStyle: .caption1)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.textColor = .secondaryLabel
        let actions = UIStackView(arrangedSubviews: [closeButton, chaptersButton, settingsButton, webButton])
        actions.axis = .horizontal
        actions.distribution = .fillEqually
        for (button, symbol, label) in [
            (closeButton, "xmark.circle.fill", "Close reader"),
            (chaptersButton, "books.vertical.fill", "Chapters"),
            (settingsButton, "slider.horizontal.3", "Reader settings"),
            (webButton, "safari.fill", "Open in browser")
        ] {
            button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold)), for: .normal)
            button.accessibilityLabel = label
            button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        }
        let stack = UIStackView(arrangedSubviews: [titleLabel, toolbar, actions])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            toolbar.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
