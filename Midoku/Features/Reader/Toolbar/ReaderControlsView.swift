import UIKit

/// A compact floating panel shared by every image and text reading mode.
final class ReaderControlsView: UIVisualEffectView {
    let toolbar = ReaderToolbarView()
    let closeButton = UIButton(type: .system)
    let chaptersButton = UIButton(type: .system)
    let panelsButton = UIButton(type: .system)
    let settingsButton = UIButton(type: .system)
    let webButton = UIButton(type: .system)
    let autoScrollButton = UIButton(type: .system)

    init() {
        super.init(effect: UIBlurEffect(style: .systemThinMaterial))
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        clipsToBounds = true
        for (button, symbol, label) in [
            (closeButton, "chevron.backward", "Go back"),
            (webButton, "safari", "Webview"),
            (chaptersButton, "list.bullet", "Chapters"),
            (panelsButton, "square.grid.3x3", "View panels"),
            (autoScrollButton, "play.fill", "Start auto scroll"),
            (settingsButton, "slider.horizontal.3", "Settings")
        ] {
            var configuration = UIButton.Configuration.plain()
            configuration.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold))
            configuration.baseForegroundColor = .label
            configuration.contentInsets = .zero
            button.configuration = configuration
            button.accessibilityLabel = label
            button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        }
        let actions = UIStackView(arrangedSubviews: [closeButton, webButton, chaptersButton, panelsButton, autoScrollButton, settingsButton])
        actions.axis = .horizontal
        actions.alignment = .center
        actions.distribution = .fillEqually
        actions.spacing = 4
        let stack = UIStackView(arrangedSubviews: [toolbar, actions])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            toolbar.heightAnchor.constraint(equalToConstant: 58)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
