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
    private static let padding = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
    /// Width a short translation may use on one line before it wraps.
    private static let readableWidth: CGFloat = 150

    /// The bubble frame for a dialogue. While translations are shown it is sized to the translation
    /// itself, centered on the original text: wide enough for the longest word, using the original's
    /// width when that gives fewer lines, and only as tall as the wrapped text.
    func bubbleFrame(covering region: CGRect, within container: CGRect) -> CGRect {
        guard showsText, let text = translationLabel.text, let font = translationLabel.font, container.width > 0 else { return region }
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let padding = Self.padding
        let longestWord = text.split(whereSeparator: \.isWhitespace)
            .map { ceil((String($0) as NSString).size(withAttributes: attributes).width) }.max() ?? 0
        let singleLine = ceil((text as NSString).size(withAttributes: attributes).width)
        let textWidth = max(min(singleLine, max(Self.readableWidth, region.width - padding.left - padding.right)), longestWord)
        let width = min(container.width - 8, textWidth + padding.left + padding.right)
        let textHeight = ceil((text as NSString).boundingRect(
            with: CGSize(width: width - padding.left - padding.right, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil).height)
        let height = textHeight + padding.top + padding.bottom
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
