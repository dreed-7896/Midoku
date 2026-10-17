import UIKit

final class TranslationAnnotationView: UIView {
    private let numberLabel = UILabel()
    private let translationLabel = UILabel()

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityTraits = .button
        layer.cornerRadius = 6
        layer.borderColor = UIColor.systemBlue.cgColor
        numberLabel.textColor = .white
        numberLabel.backgroundColor = .systemBlue
        numberLabel.font = .boldSystemFont(ofSize: 11)
        numberLabel.textAlignment = .center
        numberLabel.layer.cornerRadius = 9
        numberLabel.clipsToBounds = true
        translationLabel.textColor = .black
        translationLabel.numberOfLines = 0
        translationLabel.lineBreakMode = .byTruncatingTail
        addSubview(translationLabel)
        addSubview(numberLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var onActivate: (() -> Void)?

    override func accessibilityActivate() -> Bool {
        onActivate?()
        return true
    }

    func configure(number: Int, translation: String?, selected: Bool, showAll: Bool, fontSize: Double, opacity: Double) {
        numberLabel.text = String(number)
        translationLabel.text = translation ?? "…"
        translationLabel.font = UIFontMetrics.default.scaledFont(for: .systemFont(ofSize: CGFloat(fontSize)))
        translationLabel.isHidden = !showAll
        backgroundColor = showAll ? UIColor.white.withAlphaComponent(opacity) : UIColor.systemBlue.withAlphaComponent(selected ? 0.22 : 0.06)
        layer.borderWidth = selected ? 3 : 1
        accessibilityLabel = "Dialogue \(number), \(translation ?? "Translating")"
        accessibilityHint = "Show the full translation for this text"
        if selected { accessibilityTraits.insert(.selected) } else { accessibilityTraits.remove(.selected) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        numberLabel.frame = CGRect(x: 0, y: -8, width: max(20, numberLabel.intrinsicContentSize.width + 8), height: 20)
        translationLabel.frame = bounds.insetBy(dx: 4, dy: 6)
    }
}

final class TranslationCalloutView: UIView {
    private let titleLabel = UILabel()
    private let textView = UITextView()
    private let closeButton = UIButton(type: .close)
    var onClose: (() -> Void)?

    init() {
        super.init(frame: .zero)
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 14
        layer.borderColor = UIColor.systemBlue.cgColor
        layer.borderWidth = 1.5
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 3)
        titleLabel.font = .preferredFont(forTextStyle: .caption1)
        titleLabel.textColor = .secondaryLabel
        textView.isEditable = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textColor = .label
        closeButton.accessibilityLabel = "Close translation"
        closeButton.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .touchUpInside)
        addSubview(titleLabel)
        addSubview(closeButton)
        addSubview(textView)
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(number: Int, text: String, fontSize: Double, pageLabel: String? = nil) {
        titleLabel.text = (pageLabel.map { $0 + " · " } ?? "") + "Dialogue \(number)"
        // Preserve the reader's scroll position when the canvas moves.
        if textView.text != text { textView.text = text; textView.contentOffset = .zero }
        textView.font = UIFontMetrics.default.scaledFont(for: .systemFont(ofSize: CGFloat(max(16, fontSize))))
    }

    func fittingHeight(width: CGFloat, maximum: CGFloat) -> CGFloat {
        let textHeight = textView.sizeThatFits(CGSize(width: width - 24, height: .greatestFiniteMagnitude)).height
        return min(maximum, max(100, textHeight + 52))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        titleLabel.frame = CGRect(x: 12, y: 10, width: bounds.width - 56, height: 20)
        closeButton.frame = CGRect(x: bounds.width - 38, y: 2, width: 36, height: 36)
        textView.frame = CGRect(x: 12, y: 38, width: bounds.width - 24, height: max(0, bounds.height - 50))
    }
}
