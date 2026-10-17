import SwiftUI
import UIKit

/// The page and its annotations share the same zoom transform; the readable callout stays at screen scale.
struct TranslationPageCanvas: UIViewRepresentable {
    let image: UIImage
    let regions: [TranslationRegion]
    let translations: [Int: String]
    let fallbackText: String
    let selectedID: Int?
    let focusRequest: Int
    let webtoon: Bool
    let showAll: Bool
    let showOriginal: Bool
    let fontSize: Double
    let backgroundOpacity: Double
    let onSelect: (Int?) -> Void

    func makeUIView(context: Context) -> TranslationCanvasView {
        TranslationCanvasView()
    }

    func updateUIView(_ view: TranslationCanvasView, context: Context) {
        view.update(with: self)
    }
}

final class TranslationCanvasView: UIView, UIScrollViewDelegate {
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let connector = CAShapeLayer()
    private let callout = TranslationCalloutView()
    private var annotations: [Int: TranslationAnnotationView] = [:]
    private var configuration: TranslationPageCanvas?
    private var viewportSize: CGSize = .zero
    private var lastFocusRequest = 0
    private var needsFocus = false

    init() {
        super.init(frame: .zero)
        backgroundColor = .black
        clipsToBounds = true
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsHorizontalScrollIndicator = false
        addSubview(scrollView)
        imageView.isUserInteractionEnabled = true
        imageView.contentMode = .scaleToFill
        scrollView.addSubview(imageView)
        connector.strokeColor = UIColor.systemBlue.cgColor
        connector.fillColor = UIColor.clear.cgColor
        connector.lineWidth = 2
        layer.addSublayer(connector)
        addSubview(callout)
        callout.onClose = { [weak self] in self?.configuration?.onSelect(nil) }

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(zoomPage(_:)))
        doubleTap.numberOfTapsRequired = 2
        imageView.addGestureRecognizer(doubleTap)
        let tap = UITapGestureRecognizer(target: self, action: #selector(selectText(_:)))
        tap.require(toFail: doubleTap)
        imageView.addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(with configuration: TranslationPageCanvas) {
        let changedImage = imageView.image !== configuration.image
        let changedRegions = self.configuration?.regions != configuration.regions
        self.configuration = configuration
        if changedImage || changedRegions {
            annotations.values.forEach { $0.removeFromSuperview() }
            annotations = [:]
            for region in configuration.regions {
                let annotation = TranslationAnnotationView()
                annotation.onActivate = { [weak self] in self?.configuration?.onSelect(region.id) }
                imageView.addSubview(annotation)
                annotations[region.id] = annotation
            }
        }
        if changedImage {
            imageView.image = configuration.image
            viewportSize = .zero
        }
        if configuration.focusRequest != lastFocusRequest {
            lastFocusRequest = configuration.focusRequest
            needsFocus = true
        }
        for region in configuration.regions {
            annotations[region.id]?.configure(
                number: region.id + 1, translation: configuration.translations[region.id] ?? configuration.fallbackText,
                selected: configuration.selectedID == region.id, showAll: configuration.showAll,
                fontSize: configuration.fontSize, opacity: configuration.backgroundOpacity
            )
        }
        imageView.subviews.forEach { $0.isHidden = configuration.showOriginal }
        if let id = configuration.selectedID, let annotation = annotations[id] {
            imageView.bringSubviewToFront(annotation)
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let configuration, bounds.width > 0, bounds.height > 0 else { return }
        scrollView.frame = bounds
        let imageSize = configuration.image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        if viewportSize != bounds.size {
            // Refit on rotation or a resized window, then restore the selected text to view.
            let hadLayout = viewportSize != .zero
            viewportSize = bounds.size
            scrollView.setZoomScale(1, animated: false)
            let scale = configuration.webtoon
                ? bounds.width / imageSize.width
                : min(bounds.width / imageSize.width, bounds.height / imageSize.height)
            imageView.frame = CGRect(origin: .zero, size: CGSize(width: imageSize.width * scale, height: imageSize.height * scale))
            scrollView.contentSize = imageView.bounds.size
            scrollView.contentOffset = .zero
            needsFocus = needsFocus || (hadLayout && configuration.selectedID != nil)
        }
        centerImage()
        for region in configuration.regions {
            let rect = region.rect(in: imageView.bounds.size).insetBy(dx: -3, dy: -3)
            annotations[region.id]?.frame = rect.intersection(imageView.bounds)
        }
        if needsFocus, let id = configuration.selectedID, let region = configuration.regions.first(where: { $0.id == id }) {
            needsFocus = false
            let rect = region.rect(in: imageView.bounds.size)
            // Keep the surrounding panel visible when navigating from the list.
            let targetWidth = max(rect.width * 2.5, imageView.bounds.width / 2)
            let targetHeight = max(rect.height * 2.5, min(imageView.bounds.height, bounds.height / 2))
            scrollView.zoom(to: CGRect(x: rect.midX - targetWidth / 2, y: rect.midY - targetHeight / 2,
                                      width: targetWidth, height: targetHeight), animated: true)
        }
        positionCallout()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
        positionCallout()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        positionCallout()
    }

    private func centerImage() {
        imageView.center = CGPoint(x: max(scrollView.contentSize.width, bounds.width) / 2,
                                   y: max(scrollView.contentSize.height, bounds.height) / 2)
    }

    private func positionCallout() {
        guard let configuration, !configuration.showOriginal,
              let region = configuration.regions.first(where: { $0.id == configuration.selectedID }),
              bounds.width > 40, bounds.height > 100 else {
            callout.isHidden = true
            connector.path = nil
            return
        }
        let anchor = imageView.convert(region.rect(in: imageView.bounds.size), to: self)
        let visibleAnchor = anchor.intersection(bounds.insetBy(dx: 6, dy: 6))
        guard !visibleAnchor.isNull, !visibleAnchor.isEmpty else {
            callout.isHidden = true
            connector.path = nil
            return
        }
        callout.configure(number: region.id + 1, text: configuration.translations[region.id] ?? configuration.fallbackText,
                          fontSize: configuration.fontSize)
        let width = min(300, bounds.width - 24)
        let height = callout.fittingHeight(width: width, maximum: min(260, bounds.height * 0.48))
        let x = min(max(12, visibleAnchor.midX - width / 2), bounds.width - width - 12)
        let below = visibleAnchor.maxY + 16
        let above = visibleAnchor.minY - height - 16
        let y = below + height <= bounds.height - 12 ? below : max(12, above)
        // Prefer a side position when there is room, so the source text stays unobstructed.
        let cardX: CGFloat
        let cardY: CGFloat
        if visibleAnchor.maxX + width + 28 <= bounds.width {
            cardX = visibleAnchor.maxX + 16
            cardY = min(max(12, visibleAnchor.midY - height / 2), bounds.height - height - 12)
        } else if visibleAnchor.minX - width - 28 >= 0 {
            cardX = visibleAnchor.minX - width - 16
            cardY = min(max(12, visibleAnchor.midY - height / 2), bounds.height - height - 12)
        } else {
            cardX = x
            cardY = y
        }
        callout.frame = CGRect(x: cardX, y: cardY, width: width, height: height)
        callout.isHidden = false

        let card = callout.frame
        let start: CGPoint
        let end: CGPoint
        if card.minX >= visibleAnchor.maxX {
            start = CGPoint(x: visibleAnchor.maxX, y: visibleAnchor.midY)
            end = CGPoint(x: card.minX, y: min(max(start.y, card.minY + 16), card.maxY - 16))
        } else if card.maxX <= visibleAnchor.minX {
            start = CGPoint(x: visibleAnchor.minX, y: visibleAnchor.midY)
            end = CGPoint(x: card.maxX, y: min(max(start.y, card.minY + 16), card.maxY - 16))
        } else {
            let cardBelow = card.midY > visibleAnchor.midY
            start = CGPoint(x: visibleAnchor.midX, y: cardBelow ? visibleAnchor.maxY : visibleAnchor.minY)
            end = CGPoint(x: min(max(start.x, card.minX + 16), card.maxX - 16), y: cardBelow ? card.minY : card.maxY)
        }
        let path = UIBezierPath()
        path.move(to: start)
        path.addLine(to: end)
        connector.path = path.cgPath
    }

    @objc private func selectText(_ gesture: UITapGestureRecognizer) {
        guard let configuration, !configuration.showOriginal else { return }
        let point = gesture.location(in: imageView)
        // Resolve overlap to the smallest text area so a nearby large box cannot steal the tap.
        let hit = configuration.regions.filter {
            $0.rect(in: imageView.bounds.size).insetBy(dx: -10 / scrollView.zoomScale, dy: -10 / scrollView.zoomScale).contains(point)
        }.min {
            $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height
        }
        configuration.onSelect(hit?.id)
    }

    @objc private func zoomPage(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > 1.1 {
            scrollView.setZoomScale(1, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let size = CGSize(width: bounds.width / 2.5, height: bounds.height / 2.5)
            scrollView.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                      width: size.width, height: size.height), animated: true)
        }
    }
}

private final class TranslationAnnotationView: UIView {
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

private final class TranslationCalloutView: UIView {
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

    func configure(number: Int, text: String, fontSize: Double) {
        titleLabel.text = "Dialogue \(number)"
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
