import UIKit

final class TranslationAnnotationView: UIView {
    private let numberLabel = UILabel()
    private let translationLabel = UILabel()

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityTraits = .button
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        layer.borderColor = UIColor.systemBlue.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 3
        numberLabel.textColor = .white
        numberLabel.backgroundColor = .systemBlue
        numberLabel.font = .boldSystemFont(ofSize: 11)
        numberLabel.textAlignment = .center
        numberLabel.layer.cornerRadius = 10
        numberLabel.clipsToBounds = true
        translationLabel.textColor = .black
        // Bubbles grow to fit their translation, so text wraps by word and is never cut off.
        translationLabel.numberOfLines = 0
        translationLabel.lineBreakMode = .byWordWrapping
        translationLabel.textAlignment = .center
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
        showsText = showAll
        backgroundColor = showAll ? UIColor.white.withAlphaComponent(opacity) : UIColor.systemBlue.withAlphaComponent(selected ? 0.22 : 0.06)
        layer.borderWidth = selected ? 3 : (showAll ? 1.5 : 1)
        layer.shadowOpacity = showAll ? 0.18 : 0
        accessibilityLabel = "Dialogue \(number), \(translation ?? "Translating")"
        accessibilityHint = "Show the full translation for this text"
        if selected { accessibilityTraits.insert(.selected) } else { accessibilityTraits.remove(.selected) }
    }

    private(set) var showsText = false
    private static let padding = UIEdgeInsets(top: 10, left: 8, bottom: 8, right: 8)
    /// Width a short translation may use on one line before it wraps.
    private static let readableWidth: CGFloat = 150

    /// The bubble frame for a dialogue: it always covers the original text, and while
    /// translations are shown it widens and grows so the whole translation fits, word by word.
    func bubbleFrame(covering region: CGRect, within container: CGRect) -> CGRect {
        guard showsText, let text = translationLabel.text, let font = translationLabel.font, container.width > 0 else { return region }
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let padding = Self.padding
        let longestWord = text.split(whereSeparator: \.isWhitespace)
            .map { ceil((String($0) as NSString).size(withAttributes: attributes).width) }.max() ?? 0
        let singleLine = ceil((text as NSString).size(withAttributes: attributes).width)
        let width = min(container.width - 8,
                        max(region.width, min(singleLine, Self.readableWidth) + padding.left + padding.right,
                            longestWord + padding.left + padding.right))
        let textHeight = ceil((text as NSString).boundingRect(
            with: CGSize(width: width - padding.left - padding.right, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil).height)
        let height = max(region.height, textHeight + padding.top + padding.bottom)
        // Centered on the original text, then moved back inside the page where possible.
        var frame = CGRect(x: region.midX - width / 2, y: region.midY - height / 2, width: width, height: height)
        frame.origin.x = max(container.minX + 4, min(frame.minX, container.maxX - 4 - width))
        frame.origin.y = max(container.minY + 4, min(frame.minY, container.maxY - 4 - height))
        return frame.integral
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The badge sits on the corner, outside the text, so it never covers the first line.
        let badgeWidth = max(20, numberLabel.intrinsicContentSize.width + 8)
        numberLabel.frame = CGRect(x: -6, y: -10, width: badgeWidth, height: 20)
        translationLabel.frame = bounds.inset(by: Self.padding)
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
