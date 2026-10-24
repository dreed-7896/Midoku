import Combine
import CryptoKit
import SwiftUI
import Translation
import UIKit

@MainActor
final class ReaderTranslationCoordinator: NSObject, ObservableObject {
    private weak var owner: ReaderViewController?
    private(set) var isEnabled = false
    @Published var appleConfiguration: TranslationSession.Configuration?
    var appleRequest: ReaderAppleTranslationRequest?
    private weak var sessionHost: UIViewController?
    private var timer: Timer?
    private var displayLink: CADisplayLink?
    private let displayTarget = ReaderTranslationDisplayTarget()
    private var overlays: [ReaderTranslationImageOverlay] = []
    private var surfaces: [(ReaderTranslationSurface, String)] = []
    private var cache: [String: ReaderTranslationRecord] = [:]
    private var cacheOrder: [String] = []
    private var failures: [String: String] = [:]
    private var prefetched: [String: String] = [:]
    private let fingerprints = NSMapTable<UIImage, NSString>(keyOptions: [.weakMemory, .objectPointerPersonality], valueOptions: .strongMemory)
    private var activeTask: Task<Void, Never>?
    private var activeToken: UUID?
    private var activeKeys = Set<String>()
    private var activeLocators: [String] = []
    private var activeJob: [ReaderTranslationJobPage] = []
    private var pendingRecords: [String: ReaderTranslationRecord] = [:]
    private var recentDialogue: [(source: String, translation: String)] = []
    private var selected: (key: String, id: Int)?
    private var showAll = false
    private var original = false
    private let callout = TranslationCalloutView()
    private let connector = CAShapeLayer()
    private let accessory = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let statusLabel = UILabel()
    private let previousButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let allButton = UIButton(type: .system)
    private let listButton = UIButton(type: .system)
    private let originalButton = UIButton(type: .system)
    private let retryButton = UIButton(type: .system)
    private let appearanceButton = UIButton(type: .system)
    private let offButton = UIButton(type: .system)
    private let closeDialogueButton = UIButton(type: .system)
    private var bottomConstraint: NSLayoutConstraint?
    private var controlsVisible: Bool?

    init(owner: ReaderViewController) {
        self.owner = owner
        super.init()
        displayTarget.coordinator = self
        callout.onClose = { [weak self] in self?.select(key: nil, id: nil) }
    }

    deinit {
        timer?.invalidate()
        displayLink?.invalidate()
        activeTask?.cancel()
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        guard !enabled || owner?.reader is ReaderTranslationReader else { return }
        isEnabled = enabled
        if enabled {
            installUI()
            let timer = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
            let link = CADisplayLink(target: displayTarget, selector: #selector(ReaderTranslationDisplayTarget.tick))
            link.isPaused = true
            link.add(to: .main, forMode: .common)
            displayLink = link
            refresh()
        } else {
            stopWork()
            recentDialogue = []
            timer?.invalidate(); timer = nil
            displayLink?.invalidate(); displayLink = nil
            overlays.forEach { $0.removeFromSuperview() }; overlays = []
            surfaces = []
            selected = nil
            original = false
            accessory.isHidden = true
            callout.isHidden = true
            connector.path = nil
        }
        owner?.translationModeChanged()
    }

    func stop() { setEnabled(false) }

    func readerChanged() {
        guard isEnabled else { return }
        overlays.forEach { $0.removeFromSuperview() }; overlays = []
        surfaces = []
        select(key: nil, id: nil)
        stopWork()
        if owner?.reader is ReaderTranslationReader { refresh() } else { stop() }
    }

    private var providerKey: String {
        TranslationSettings.usesAPI
            ? "api|\(TranslationSettings.endpoint)|\(TranslationSettings.model)"
            : "apple-ja-en"
    }

    private func key(page: Page, image: UIImage) -> String {
        let digest: String
        if let known = fingerprints.object(forKey: image) {
            digest = known as String
        } else {
            let bytes: Data
            if let raw = image.cgImage?.dataProvider?.data { bytes = raw as Data }
            else { bytes = image.pngData() ?? Data() }
            digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
                + "|\(image.size.width)x\(image.size.height)|\(image.imageOrientation.rawValue)"
            fingerprints.setObject(digest as NSString, forKey: image)
        }
        let identity = owner?.translationIdentity(for: page)
        // Content fingerprint distinguishes split halves and processing settings. Physical tuples
        // distinguish collection variants that use the same chapter key on different sources.
        let components = [identity?.sourceKey ?? page.sourceId, identity?.mangaKey ?? "", identity?.chapterKey ?? page.chapterId,
                          digest, providerKey,
                          owner?.readingMode == .webtoon || owner?.readingMode == .continuous ? "scroll" : "paged"]
        return String(decoding: (try? JSONEncoder().encode(components)) ?? Data(), as: UTF8.self)
    }

    private func locator(for page: Page) -> String {
        let identity = owner?.translationIdentity(for: page)
        return "\(identity?.sourceKey ?? page.sourceId)|\(identity?.mangaKey ?? "")|\(identity?.chapterKey ?? page.chapterId)"
            + "|\(page.imageURL ?? "")|\(page.zipURL ?? "")|\(page.base64?.hashValue ?? 0)"
            + "|\(page.image.map { ObjectIdentifier($0).hashValue } ?? 0)|\(ImageProcessingSettingsKey.getProcessorSettingsKey())|\(providerKey)"
    }

    func pageImageChanged() {
        guard isEnabled else { return }
        refresh()
    }

    private func refresh() {
        guard isEnabled, let owner, owner.viewIfLoaded?.window != nil,
              let reader = owner.reader as? ReaderTranslationReader else { return }
        let visible = Array(reader.translationSurfaces().prefix(6))
        surfaces = visible.compactMap { surface in
            guard let image = surface.imageView.image else { return nil }
            return (surface, key(page: surface.page, image: image))
        }
        let liveViews = Set(visible.map { ObjectIdentifier($0.imageView) })
        overlays.removeAll { overlay in
            let keep = overlay.imageView.map { liveViews.contains(ObjectIdentifier($0)) && $0.image === overlay.expectedImage && overlay.superview === $0 } ?? false
            if !keep { overlay.removeFromSuperview() }
            return !keep
        }
        if let selected, !surfaces.contains(where: { $0.1 == selected.key }) { self.selected = nil }
        for (surface, key) in surfaces {
            let overlay: ReaderTranslationImageOverlay
            if let existing = overlays.first(where: { $0.imageView === surface.imageView }) {
                overlay = existing
            } else if let image = surface.imageView.image {
                overlay = ReaderTranslationImageOverlay(imageView: surface.imageView, image: image)
                overlays.append(overlay)
            } else { continue }
            overlay.key = key
            overlay.onSelect = { [weak self] id in self?.select(key: key, id: id) }
            surface.imageView.bringSubviewToFront(overlay)
            overlay.configure(record: record(for: key) ?? pendingRecords[key],
                              selectedID: selected?.key == key ? selected?.id : nil, showAll: showAll, original: original)
        }
        var seen = Set<String>()
        let needed = surfaces.filter { record(for: $0.1) == nil && failures[$0.1] == nil && seen.insert($0.1).inserted }
        if !needed.isEmpty {
            // New visible pages take priority over an off-screen request or speculative prefetch.
            if activeToken != nil, !needed.contains(where: { activeKeys.contains($0.1) }),
               !surfaces.contains(where: { activeKeys.contains($0.1) }) { stopWork() }
            if activeToken == nil {
                // Every visible page (a spread, or several webtoon strips) goes out in one request.
                start(needed.compactMap { surface, key in surface.imageView.image.map { (key, $0) } })
            }
        } else if activeToken == nil, !surfaces.isEmpty {
            let upcoming = reader.nextTranslationPages(limit: Self.prefetchPageCount)
                .filter { !$0.isTextPage }
                .map { (page: $0, locator: locator(for: $0)) }
                .filter { prefetched[$0.locator].flatMap { record(for: $0) } == nil && failures[$0.locator] == nil }
            if !upcoming.isEmpty { prefetch(upcoming) }
        }
        updateStatus()
        positionCallout()
    }

    /// Pages translated ahead in a single request; more pages per request means fewer requests
    /// and more surrounding dialogue for the model.
    private static let prefetchPageCount = 3
    /// Dialogue already translated in this session, sent as read-only context with each request.
    private static let contextLineCount = 30

    private func start(_ pages: [(key: String, image: UIImage)]) {
        let token = UUID()
        activeToken = token
        activeKeys = Set(pages.map(\.key))
        activeTask = Task { [weak self] in
            guard let self else { return }
            var jobPages: [ReaderTranslationJobPage] = []
            for page in pages {
                guard let regions = await recognize(page.image, token: token) else { return }
                jobPages.append(ReaderTranslationJobPage(key: page.key, locator: nil, regions: regions))
                showPending(jobPages.last!)
            }
            await translate(jobPages, token: token)
        }
    }

    private func prefetch(_ pages: [(page: Page, locator: String)]) {
        let token = UUID()
        activeToken = token
        activeLocators = pages.map(\.locator)
        activeTask = Task { [weak self] in
            guard let self, let owner = self.owner else { return }
            var jobPages: [ReaderTranslationJobPage] = []
            for (page, locator) in pages {
                guard let image = await owner.loadTranslationImage(for: page), !Task.isCancelled, activeToken == token else {
                    guard !Task.isCancelled, activeToken == token else { return }
                    // Translate the pages that did load; Retry tries the missing one again.
                    failures[locator] = "Next page could not be loaded."
                    activeLocators.removeAll { $0 == locator }
                    break
                }
                let cacheKey = self.key(page: page, image: image)
                prefetched[locator] = cacheKey
                if record(for: cacheKey) != nil { continue }
                activeKeys.insert(cacheKey)
                guard let regions = await recognize(image, token: token) else { return }
                jobPages.append(ReaderTranslationJobPage(key: cacheKey, locator: locator, regions: regions))
                showPending(jobPages.last!)
            }
            guard activeToken == token else { return }
            if jobPages.isEmpty { stopWork(); render(); return }
            await translate(jobPages, token: token)
        }
    }

    private func recognize(_ image: UIImage, token: UUID) async -> [TranslationRegion]? {
        let webtoon = owner?.readingMode == .webtoon || owner?.readingMode == .continuous
        let regions = await PageTranslator.recognize([image], webtoon: webtoon)
        guard !Task.isCancelled, activeToken == token else { return nil }
        return regions
    }

    private func showPending(_ page: ReaderTranslationJobPage) {
        pendingRecords[page.key] = ReaderTranslationRecord(regions: page.regions, translations: [:])
        render()
    }

    /// Sends the dialogue of every page in the job together, with ids made unique across pages.
    private func translate(_ pages: [ReaderTranslationJobPage], token: UUID) async {
        let pages = ReaderTranslationJobPage.offsets(pages)
        activeJob = pages
        let regions = ReaderTranslationJobPage.combinedRegions(pages)
        if regions.isEmpty { finish(token: token, translations: [:], error: nil); return }
        if TranslationSettings.usesAPI {
            do {
                let translations = try await PageTranslator.translateWithAPI(regions, context: recentDialogue)
                guard !Task.isCancelled, activeToken == token else { return }
                finish(token: token, translations: translations, error: nil)
            } catch {
                guard !Task.isCancelled, activeToken == token else { return }
                finish(token: token, translations: [:], error: error.localizedDescription)
            }
        } else {
            appleRequest = ReaderAppleTranslationRequest(token: token, regions: regions)
            if appleConfiguration == nil {
                appleConfiguration = TranslationSession.Configuration(source: Locale.Language(identifier: "ja"),
                                                                      target: Locale.Language(identifier: "en"))
            } else { appleConfiguration?.invalidate() }
        }
    }

    func appleFinished(token: UUID, translations: [Int: String], error: String?) {
        finish(token: token, translations: translations, error: error)
    }

    private func finish(token: UUID, translations: [Int: String], error: String?) {
        guard activeToken == token else { return }
        if let error {
            for key in activeKeys { failures[key] = error }
            for locator in activeLocators { failures[locator] = error }
        } else {
            if failures.count > 80 { failures.removeAll() }
            if prefetched.count > 80 { prefetched.removeAll() }
            for page in activeJob {
                let local = page.translations(from: translations)
                let record = ReaderTranslationRecord(regions: page.regions, translations: local)
                remember(record, for: page.key)
                TranslationStore.shared.save(record, for: page.key)
                recentDialogue += page.regions.compactMap { region in
                    local[region.id].map { (source: region.sourceText, translation: $0) }
                }
            }
            recentDialogue = Array(recentDialogue.suffix(Self.contextLineCount))
        }
        stopWork()
        render()
    }

    /// Memory first, then translations saved on device within the last 30 days.
    private func record(for key: String) -> ReaderTranslationRecord? {
        if let record = cache[key] { return record }
        guard let stored = TranslationStore.shared.record(for: key) else { return nil }
        remember(stored, for: key)
        return stored
    }

    private func remember(_ record: ReaderTranslationRecord, for key: String) {
        cache[key] = record
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
        while cacheOrder.count > 40 { cache.removeValue(forKey: cacheOrder.removeFirst()) }
    }

    private func stopWork() {
        activeToken = nil
        activeKeys = []
        activeLocators = []
        activeJob = []
        pendingRecords = [:]
        activeTask?.cancel()
        activeTask = nil
        appleRequest = nil
        appleConfiguration = nil
    }

    private func render() {
        for overlay in overlays {
            overlay.configure(record: record(for: overlay.key) ?? pendingRecords[overlay.key],
                              selectedID: selected?.key == overlay.key ? selected?.id : nil, showAll: showAll, original: original)
        }
        updateStatus()
        positionCallout()
    }

    private func updateStatus() {
        let error = surfaces.compactMap { failures[$0.1] }.first
        let records = surfaces.compactMap { record(for: $0.1) }
        if let error { statusLabel.text = error }
        else if surfaces.isEmpty { statusLabel.text = "Translation on · swipe pages or scroll normally" }
        else if records.count < surfaces.count { statusLabel.text = "Translating page… · keep reading" }
        else if records.allSatisfy({ $0.regions.isEmpty }) { statusLabel.text = "No Japanese dialogue found" }
        else { statusLabel.text = showAll ? "Tap a translation to expand" : "Tap marked text · swipe pages or scroll normally" }
        // While a dialogue is selected, the toolbar only steps through dialogues or closes the selection.
        let stepping = selected != nil
        for button in [allButton, listButton, originalButton, appearanceButton, offButton] { button.isHidden = stepping }
        retryButton.isHidden = stepping || error == nil
        closeDialogueButton.isHidden = !stepping
        listButton.isEnabled = !overlays.allSatisfy { $0.record?.regions.isEmpty != false }
        let sequence = bubbleSequence()
        let position = selected.flatMap { selected in sequence.firstIndex { $0.key == selected.key && $0.id == selected.id } }
        previousButton.isEnabled = !sequence.isEmpty && position != 0
        nextButton.isEnabled = !sequence.isEmpty && position != sequence.count - 1
        if error == nil, let position { statusLabel.text = "Dialogue \(position + 1) of \(sequence.count)" }
        allButton.setImage(UIImage(systemName: showAll ? "hand.tap" : "text.bubble"), for: .normal)
        allButton.accessibilityLabel = showAll ? "Use tap translation" : "Show all translations"
        updateControlPosition()
    }

    private func select(key: String?, id: Int?) {
        selected = key.flatMap { key in id.map { (key: key, id: $0) } }
        render()
    }

    func handleTap(at point: CGPoint) -> Bool {
        guard isEnabled, !original, let owner else { return false }
        for overlay in overlays {
            let local = owner.view.convert(point, to: overlay)
            if let region = overlay.region(at: local) { select(key: overlay.key, id: region.id); return true }
        }
        if selected != nil { select(key: nil, id: nil); return true }
        return false
    }

    /// Visible bubbles in reading order: pages in the order they appear, then each page's dialogue order.
    private func bubbleSequence() -> [(key: String, id: Int)] {
        var seen = Set<String>()
        return surfaces.map { $0.1 }.filter { seen.insert($0).inserted }.flatMap { key in
            (record(for: key)?.regions ?? []).map { (key: key, id: $0.id) }
        }
    }

    @objc private func selectPrevious() { step(by: -1) }
    @objc private func closeDialogue() { select(key: nil, id: nil) }
    @objc private func selectNext() { step(by: 1) }

    /// Moves the selection to the neighboring bubble. With nothing selected, next starts at the
    /// first bubble and previous at the last.
    private func step(by offset: Int) {
        let sequence = bubbleSequence()
        guard !sequence.isEmpty else { return }
        let current = selected.flatMap { selected in sequence.firstIndex { $0.key == selected.key && $0.id == selected.id } }
        let index = current.map { $0 + offset } ?? (offset > 0 ? 0 : sequence.count - 1)
        guard sequence.indices.contains(index) else { return }
        let target = sequence[index]
        select(key: target.key, id: target.id)
        UISelectionFeedbackGenerator().selectionChanged()
        reveal(key: target.key, id: target.id)
    }

    /// Scrolls a bubble into view only when it is not already fully visible, so stepping through a
    /// page does not move or zoom it.
    private func reveal(key: String, id: Int) {
        guard let owner, let overlay = overlays.first(where: { $0.key == key }), let imageView = overlay.imageView,
              let region = overlay.record?.regions.first(where: { $0.id == id }) else { return }
        let rect = overlay.rect(for: region)
        let visible = owner.view.bounds.inset(by: owner.view.safeAreaInsets)
        guard !visible.contains(overlay.convert(rect, to: owner.view)) else { return }
        (owner.reader as? ReaderTranslationReader)?.revealTranslation(rect, in: imageView)
    }

    @objc private func toggleAll() { showAll.toggle(); render() }
    @objc private func showOriginal() { original = true; render() }
    @objc private func hideOriginal() { original = false; render() }
    @objc private func disable() { stop() }
    @objc private func retry() { failures.removeAll(); refresh() }

    private func pageLabel(for key: String) -> String {
        if let surface = surfaces.first(where: { $0.1 == key })?.0,
           let index = owner?.pages.firstIndex(of: surface.page) { return "Page \(index + 1)" }
        let index = surfaces.firstIndex(where: { $0.1 == key }) ?? 0
        return "Visible page \(index + 1)"
    }

    @objc private func openList() {
        let items = overlays.flatMap { overlay in
            (overlay.record?.regions ?? []).map {
                ReaderTranslationListItem(key: overlay.key, region: $0, pageLabel: pageLabel(for: overlay.key),
                                          translation: overlay.record?.translations[$0.id] ?? "Translating…")
            }
        }
        let current = selected.map { "\($0.key):\($0.id)" }
        let list = ReaderTranslationListView(items: items, selected: current) { [weak self] item in
            guard let self, let owner, let overlay = overlays.first(where: { $0.key == item.key }), let imageView = overlay.imageView else { return }
            select(key: item.key, id: item.region.id)
            (owner.reader as? ReaderTranslationReader)?.revealTranslation(overlay.rect(for: item.region), in: imageView)
        }
        (owner?.reader as? ReaderWebtoonViewController)?.pauseAutoScroll()
        let view = list.onDisappear { [weak self] in
            (self?.owner?.reader as? ReaderWebtoonViewController)?.resumeAutoScroll()
        }
        owner?.present(UIHostingController(rootView: view), animated: true)
    }

    @objc private func openAppearance() {
        (owner?.reader as? ReaderWebtoonViewController)?.pauseAutoScroll()
        let view = ReaderTranslationAppearanceView().onDisappear { [weak self] in
            (self?.owner?.reader as? ReaderWebtoonViewController)?.resumeAutoScroll()
        }
        owner?.present(UIHostingController(rootView: view), animated: true)
    }

    private func installUI() {
        guard let owner else { return }
        if sessionHost == nil {
            let host = UIHostingController(rootView: ReaderTranslationSessionView(coordinator: self))
            owner.addChild(host)
            host.view.backgroundColor = .clear
            host.view.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
            owner.view.addSubview(host.view)
            host.didMove(toParent: owner)
            sessionHost = host
        }
        if accessory.superview == nil {
            accessory.layer.cornerRadius = 18
            accessory.clipsToBounds = true
            let buttons = [previousButton, nextButton, allButton, listButton, originalButton, appearanceButton, retryButton, offButton,
                           closeDialogueButton]
            let symbols = ["chevron.left", "chevron.right", "text.bubble", "list.number", "eye", "textformat.size", "arrow.clockwise", "xmark",
                           "xmark.circle"]
            let labels = ["Previous dialogue", "Next dialogue", "Show all translations", "Dialogue list", "Hold to show original",
                          "Translation appearance", "Retry translation", "Disable translation", "Close dialogue"]
            for (index, button) in buttons.enumerated() {
                button.setImage(UIImage(systemName: symbols[index]), for: .normal)
                button.accessibilityLabel = labels[index]
                button.heightAnchor.constraint(equalToConstant: 40).isActive = true
            }
            previousButton.addTarget(self, action: #selector(selectPrevious), for: .touchUpInside)
            nextButton.addTarget(self, action: #selector(selectNext), for: .touchUpInside)
            allButton.addTarget(self, action: #selector(toggleAll), for: .touchUpInside)
            listButton.addTarget(self, action: #selector(openList), for: .touchUpInside)
            originalButton.addTarget(self, action: #selector(showOriginal), for: .touchDown)
            originalButton.addTarget(self, action: #selector(hideOriginal), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
            appearanceButton.addTarget(self, action: #selector(openAppearance), for: .touchUpInside)
            retryButton.addTarget(self, action: #selector(retry), for: .touchUpInside)
            offButton.addTarget(self, action: #selector(disable), for: .touchUpInside)
            closeDialogueButton.addTarget(self, action: #selector(closeDialogue), for: .touchUpInside)
            closeDialogueButton.isHidden = true
            let row = UIStackView(arrangedSubviews: buttons)
            row.distribution = .fillEqually
            statusLabel.font = .preferredFont(forTextStyle: .caption2)
            statusLabel.textColor = .secondaryLabel
            statusLabel.textAlignment = .center
            statusLabel.numberOfLines = 2
            let stack = UIStackView(arrangedSubviews: [statusLabel, row])
            stack.axis = .vertical
            stack.translatesAutoresizingMaskIntoConstraints = false
            accessory.contentView.addSubview(stack)
            accessory.translatesAutoresizingMaskIntoConstraints = false
            owner.view.addSubview(accessory)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: accessory.contentView.leadingAnchor, constant: 8),
                stack.trailingAnchor.constraint(equalTo: accessory.contentView.trailingAnchor, constant: -8),
                stack.topAnchor.constraint(equalTo: accessory.contentView.topAnchor, constant: 8),
                stack.bottomAnchor.constraint(equalTo: accessory.contentView.bottomAnchor, constant: -4),
                accessory.centerXAnchor.constraint(equalTo: owner.view.centerXAnchor),
                accessory.widthAnchor.constraint(lessThanOrEqualToConstant: 340),
                accessory.leadingAnchor.constraint(greaterThanOrEqualTo: owner.view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
                accessory.trailingAnchor.constraint(lessThanOrEqualTo: owner.view.safeAreaLayoutGuide.trailingAnchor, constant: -12)
            ])
            let width = accessory.widthAnchor.constraint(equalToConstant: 340)
            width.priority = .defaultHigh
            width.isActive = true
            connector.strokeColor = UIColor.systemBlue.cgColor
            connector.fillColor = UIColor.clear.cgColor
            connector.lineWidth = 2
            owner.view.layer.addSublayer(connector)
            owner.view.addSubview(callout)
        }
        accessory.isHidden = false
        owner.view.bringSubviewToFront(accessory)
        owner.view.bringSubviewToFront(callout)
        updateControlPosition()
    }

    func updateControlPosition() {
        guard isEnabled, let owner, accessory.superview != nil else { return }
        guard controlsVisible != owner.readerControlsVisible || bottomConstraint == nil else { return }
        controlsVisible = owner.readerControlsVisible
        bottomConstraint?.isActive = false
        bottomConstraint = owner.readerControlsVisible
            ? accessory.bottomAnchor.constraint(equalTo: owner.controlsView.topAnchor, constant: -8)
            : accessory.bottomAnchor.constraint(equalTo: owner.view.safeAreaLayoutGuide.bottomAnchor, constant: -8)
        bottomConstraint?.isActive = true
    }

    func positionCallout() {
        displayLink?.isPaused = selected == nil || original
        guard isEnabled, !original, let owner, let selected,
              let overlay = overlays.first(where: { $0.key == selected.key }), overlay.superview != nil,
              overlay.imageView?.image === overlay.expectedImage,
              let region = overlay.record?.regions.first(where: { $0.id == selected.id }) else {
            callout.isHidden = true; connector.path = nil; return
        }
        let available = owner.view.bounds.inset(by: owner.view.safeAreaInsets)
        let maxY = accessory.isHidden ? available.maxY : accessory.frame.minY - 8
        let viewport = CGRect(x: available.minX + 12, y: available.minY + 12,
                              width: max(0, available.width - 24), height: max(0, maxY - available.minY - 24))
        // Anchor to the drawn bubble so the tooltip never covers it.
        let anchor = overlay.convert(overlay.displayedRect(for: region), to: owner.view).intersection(viewport)
        guard viewport.width > 40, viewport.height > 80, !anchor.isNull, !anchor.isEmpty else {
            callout.isHidden = true; connector.path = nil; return
        }
        let font = UserDefaults.standard.object(forKey: "Translation.overlayFontSize") as? Double ?? 14
        callout.configure(number: region.id + 1, text: overlay.record?.translations[region.id] ?? "Translating…",
                          fontSize: font, pageLabel: pageLabel(for: selected.key))
        let width = min(300, viewport.width)
        let height = callout.fittingHeight(width: width, maximum: min(240, viewport.height * 0.5))
        let x = min(max(viewport.minX, anchor.midX - width / 2), viewport.maxX - width)
        let below = anchor.maxY + 14
        let y = below + height <= viewport.maxY ? below : max(viewport.minY, anchor.minY - height - 14)
        callout.frame = CGRect(x: x, y: y, width: width, height: height)
        callout.isHidden = false
        let cardBelow = callout.frame.midY > anchor.midY
        let start = CGPoint(x: anchor.midX, y: cardBelow ? anchor.maxY : anchor.minY)
        let end = CGPoint(x: min(max(start.x, x + 16), x + width - 16), y: cardBelow ? y : y + height)
        let path = UIBezierPath(); path.move(to: start); path.addLine(to: end)
        connector.path = path.cgPath
    }
}

private final class ReaderTranslationDisplayTarget: NSObject {
    weak var coordinator: ReaderTranslationCoordinator?
    @MainActor @objc func tick() { coordinator?.positionCallout() }
}
