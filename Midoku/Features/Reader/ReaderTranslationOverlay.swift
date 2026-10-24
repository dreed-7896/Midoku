import UIKit

struct ReaderTranslationSurface {
    let page: Page
    let imageView: UIImageView
}

@MainActor
protocol ReaderTranslationReader: ReaderReaderDelegate {
    func translationSurfaces() -> [ReaderTranslationSurface]
    func revealTranslation(_ rect: CGRect, in imageView: UIImageView)
}

/// One page of a batched translation request. Region ids are page-local; `offset` makes them
/// unique within the request so several pages can be translated together.
struct ReaderTranslationJobPage {
    let key: String
    let locator: String?
    let regions: [TranslationRegion]
    var offset = 0

    /// Expects pages whose offsets were assigned by `offsets(_:)`.
    static func combinedRegions(_ pages: [ReaderTranslationJobPage]) -> [TranslationRegion] {
        pages.flatMap { page in
            page.regions.map { TranslationRegion(id: page.offset + $0.id, imageIndex: $0.imageIndex, sourceText: $0.sourceText, bounds: $0.bounds) }
        }
    }

    static func offsets(_ pages: [ReaderTranslationJobPage]) -> [ReaderTranslationJobPage] {
        var next = 0
        return pages.map { page in
            var page = page
            page.offset = next
            next += (page.regions.map(\.id).max() ?? -1) + 1
            return page
        }
    }

    func translations(from combined: [Int: String]) -> [Int: String] {
        Dictionary(uniqueKeysWithValues: regions.compactMap { region in combined[offset + region.id].map { (region.id, $0) } })
    }
}

final class ReaderTranslationRecord {
    let regions: [TranslationRegion]
    let translations: [Int: String]

    init(regions: [TranslationRegion], translations: [Int: String]) {
        self.regions = regions
        self.translations = translations
    }
}

/// Lives inside the real image view, so annotations follow native zoom and webtoon layout.
final class ReaderTranslationImageOverlay: UIView {
    weak var imageView: UIImageView?
    weak var expectedImage: UIImage?
    var key = ""
    private(set) var record: ReaderTranslationRecord?
    private var annotations: [Int: TranslationAnnotationView] = [:]
    private var selectedID: Int?
    private var showAll = false
    private var fontSize: Double = 14
    private var opacity: Double = 0.94
    var onSelect: ((Int) -> Void)?

    init(imageView: UIImageView, image: UIImage) {
        self.imageView = imageView
        self.expectedImage = image
        super.init(frame: imageView.bounds)
        backgroundColor = .clear
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.addSubview(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func remove(from imageView: UIImageView) {
        imageView.subviews.compactMap { $0 as? ReaderTranslationImageOverlay }.forEach { $0.removeFromSuperview() }
    }

    var imageRect: CGRect {
        guard let imageView, let image = expectedImage, imageView.image === image,
              image.size.width > 0, image.size.height > 0 else { return .zero }
        guard imageView.contentMode == .scaleAspectFit else { return bounds }
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    func rect(for region: TranslationRegion) -> CGRect {
        let area = imageRect
        return region.rect(in: area.size).offsetBy(dx: area.minX, dy: area.minY)
    }

    func configure(record: ReaderTranslationRecord?, selectedID: Int?, showAll: Bool) {
        let font = UserDefaults.standard.object(forKey: "Translation.overlayFontSize") as? Double ?? 14
        let background = UserDefaults.standard.object(forKey: "Translation.overlayOpacity") as? Double ?? 0.94
        isHidden = imageView?.image !== expectedImage
        let changed = self.record !== record || self.selectedID != selectedID || self.showAll != showAll
            || fontSize != font || opacity != background
        guard changed else { return }
        if self.record?.regions != record?.regions {
            annotations.values.forEach { $0.removeFromSuperview() }
            annotations = [:]
            for region in record?.regions ?? [] {
                let annotation = TranslationAnnotationView()
                annotation.onActivate = { [weak self] in self?.onSelect?(region.id) }
                annotations[region.id] = annotation
                addSubview(annotation)
            }
        }
        self.record = record
        self.selectedID = selectedID
        self.showAll = showAll
        fontSize = font
        opacity = background
        for region in record?.regions ?? [] {
            // The selected dialogue always shows its translated bubble over the original text,
            // also in tap mode, so jumping with previous/next shows both the bubble and its tooltip.
            let showsBubble = (showAll || selectedID == region.id) && record?.translations[region.id] != nil
            annotations[region.id]?.configure(number: region.id + 1, translation: record?.translations[region.id],
                                               selected: selectedID == region.id, showAll: showsBubble,
                                               fontSize: font, opacity: background)
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if imageView?.image !== expectedImage { isHidden = true; return }
        let container = imageRect.intersection(bounds)
        for region in record?.regions ?? [] {
            guard let annotation = annotations[region.id] else { continue }
            annotation.frame = annotation.bubbleFrame(covering: rect(for: region).insetBy(dx: -3, dy: -3).intersection(bounds),
                                                      within: container)
        }
        // The selected bubble stays on top where bubbles overlap.
        if let selectedID, let selected = annotations[selectedID] { bringSubviewToFront(selected) }
    }

    func region(at point: CGPoint) -> TranslationRegion? {
        guard imageView?.image === expectedImage, !isHidden else { return nil }
        // Shown bubbles can be larger than the original text, so taps use the bubble's own frame.
        func area(_ region: TranslationRegion) -> CGRect {
            if let annotation = annotations[region.id], annotation.showsText, !annotation.frame.isEmpty { return annotation.frame }
            return rect(for: region).insetBy(dx: -5, dy: -5)
        }
        return record?.regions.filter { area($0).contains(point) }
            .min { area($0).width * area($0).height < area($1).width * area($1).height }
    }

    // Leave blank areas to the reader's existing tap zones. On text, the reader's tap handler
    // handles translation before dictionary lookup. Native pan/pinch recognizers still work.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, region(at: point) != nil else { return nil }
        return self
    }
}
