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
    private var overlays: [ReaderTranslationImageOverlay] = []
    private var surfaces: [(ReaderTranslationSurface, String)] = []
    private var cache: [String: ReaderTranslationRecord] = [:]
    private var cacheOrder: [String] = []
    private var failures: [String: String] = [:]
    private var prefetched: [String: String] = [:]
    /// Pages the reader asked to translate (the pages in view, or pages chosen in the options), in
    /// reading order, until translated. Nothing else is sent, so no request is made without asking.
    private var requested: [(page: Page, locator: String)] = []
    private let fingerprints = NSMapTable<UIImage, NSString>(keyOptions: [.weakMemory, .objectPointerPersonality], valueOptions: .strongMemory)
    private var activeTask: Task<Void, Never>?
    private var activeToken: UUID?
    private var activeKeys = Set<String>()
    private var activeLocators: [String] = []
    private var activeJob: [ReaderTranslationJobPage] = []
    private var activeIsPrefetch = false
    private var pendingRecords: [String: ReaderTranslationRecord] = [:]
    private var recentDialogue: [(source: String, translation: String)] = []
    private var selected: (key: String, id: Int)?
    private var showAll = false
    private let accessory = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let statusLabel = UILabel()
    private let previousButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let allButton = UIButton(type: .system)
    private let listButton = UIButton(type: .system)
    private let translateButton = UIButton(type: .system)
    private let retryButton = UIButton(type: .system)
    private let optionsButton = UIButton(type: .system)
    private let closeDialogueButton = UIButton(type: .system)
    private var bottomConstraint: NSLayoutConstraint?
    private var controlsVisible: Bool?

    init(owner: ReaderViewController) {
        self.owner = owner
        super.init()
    }

    deinit {
        timer?.invalidate()
        activeTask?.cancel()
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        guard !enabled || owner?.reader is ReaderTranslationReader else { return }
        isEnabled = enabled
        requested = []
        if enabled {
            installUI()
            let timer = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
            refresh()
        } else {
            stopWork()
            recentDialogue = []
            timer?.invalidate(); timer = nil
            overlays.forEach { $0.removeFromSuperview() }; overlays = []
            surfaces = []
            selected = nil
            accessory.isHidden = true
        }
        owner?.translationModeChanged()
    }

    func stop() { setEnabled(false) }

    /// Translates the pages in view, and nothing else.
    @objc private func translateVisible() {
        request(surfaces.map { $0.0.page })
    }

    /// Translates pages of the current chapter, numbered from 1, in batches of the pages-at-a-time setting.
    func translatePages(_ numbers: [Int]) {
        guard let pages = owner?.pages else { return }
        request(numbers.filter { pages.indices.contains($0 - 1) }.map { pages[$0 - 1] })
    }

    /// Translates the default number of pages (the pages-at-a-time setting), starting with the page being read.
    func translateNextPages() {
        guard let owner, let current = owner.currentTranslationPage.flatMap({ owner.pages.firstIndex(of: $0) }) else { return }
        translatePages(Array((current + 1)...(current + TranslationSettings.pagesPerRequest)))
    }

    private func request(_ pages: [Page]) {
        guard isEnabled else { return }
        let known = Set(requested.map(\.locator))
        let new = pages.filter { $0.type == .imagePage && !$0.isTextPage }.map { (page: $0, locator: locator(for: $0)) }
        for item in new { failures[item.locator] = nil }
        requested += new.filter { !known.contains($0.locator) && !isTranslated($0.locator) }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        refresh()
    }

    func openOptions() {
        guard let owner else { return }
        (owner.reader as? ReaderWebtoonViewController)?.pauseAutoScroll()
        let view = ReaderTranslationOptionsView(
            pageCount: owner.pages.count,
            currentPage: owner.currentTranslationPage.flatMap { owner.pages.firstIndex(of: $0) }.map { $0 + 1 } ?? 1,
            translatePages: { [weak self] in self?.translatePages($0) },
            translateNextPages: { [weak self] in self?.translateNextPages() }
        ).onDisappear { [weak self] in
            (self?.owner?.reader as? ReaderWebtoonViewController)?.resumeAutoScroll()
        }
        owner.present(UIHostingController(rootView: view), animated: true)
    }

    private func isTranslated(_ locator: String) -> Bool {
        prefetched[locator].flatMap { record(for: $0) } != nil
    }

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
            // Remember which page this translation belongs to, so requested pages skip it.
            if record(for: key) != nil { prefetched[locator(for: surface.page)] = key }
            overlay.configure(record: record(for: key) ?? pendingRecords[key],
                              selectedID: selected?.key == key ? selected?.id : nil, showAll: showAll)
        }
        requested.removeAll { isTranslated($0.locator) }
        let requestedLocators = Set(requested.map(\.locator))
        var seen = Set<String>()
        let needed = surfaces.filter { surface, key in
            record(for: key) == nil && failures[key] == nil && seen.insert(key).inserted
                && requestedLocators.contains(locator(for: surface.page))
        }
        if !needed.isEmpty {
            // Requested pages in view take priority over requested pages off screen.
            if activeToken != nil, !needed.contains(where: { activeKeys.contains($0.1) }),
               !surfaces.contains(where: { activeKeys.contains($0.1) }) { stopWork() }
            // A large batch can take a while to prepare. If the reader reaches one of its pages before
            // the batch is sent, translate the visible page now and continue the batch afterwards.
            if activeToken != nil, activeIsPrefetch, activeJob.isEmpty { stopWork() }
            if activeToken == nil {
                // Every visible page (a spread, or several webtoon strips) goes out in one request.
                start(needed.compactMap { surface, key in surface.imageView.image.map { (key, $0) } })
            }
        } else if activeToken == nil, !surfaces.isEmpty,
                  // A page in view that just failed waits for Retry instead of being sent again.
                  case let failedInView = Set(surfaces.filter { failures[$0.1] != nil }.map { locator(for: $0.0.page) }),
                  case let batch = requested.filter({ failures[$0.locator] == nil && !failedInView.contains($0.locator) })
                      .prefix(TranslationSettings.pagesPerRequest),
                  !batch.isEmpty {
            // Requested pages off screen, in batches.
            prefetch(Array(batch))
        }
        updateStatus()
    }

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
        activeIsPrefetch = true
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
            if prefetched.count > 400 { prefetched.removeAll() }
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

    /// Memory first, then translations saved on device (kept while the title is in the library).
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
        activeIsPrefetch = false
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
                              selectedID: selected?.key == overlay.key ? selected?.id : nil, showAll: showAll)
        }
        updateStatus()
    }

    private func updateStatus() {
        // Chosen pages that are not on screen report their error once none of them can continue.
        let requestError = requested.allSatisfy { failures[$0.locator] != nil } ? requested.lazy.compactMap { self.failures[$0.locator] }.first : nil
        let error = surfaces.compactMap { failures[$0.1] }.first ?? requestError
        let records = surfaces.compactMap { record(for: $0.1) }
        if let error { statusLabel.text = error }
        else if surfaces.isEmpty { statusLabel.text = "Translation on · swipe pages or scroll normally" }
        else if !requested.isEmpty {
            statusLabel.text = requested.count == 1 ? "Translating 1 page… · keep reading" : "Translating \(requested.count) pages… · keep reading"
        }
        else if records.count < surfaces.count {
            statusLabel.text = "Tap the translate button to translate the pages in view"
        }
        else if records.allSatisfy({ $0.regions.isEmpty }) { statusLabel.text = "No Japanese dialogue found" }
        else { statusLabel.text = showAll ? "Tap a translation to select it" : "Tap marked text · swipe pages or scroll normally" }
        // While a dialogue is selected, the toolbar only steps through dialogues or closes the selection.
        let stepping = selected != nil
        for button in [allButton, listButton, translateButton, optionsButton] { button.isHidden = stepping }
        translateButton.isEnabled = surfaces.contains { record(for: $0.1) == nil }
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
        guard isEnabled, let owner else { return false }
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
        // The webtoon reader centers each dialogue; paged readers keep the page still when it is already visible.
        guard owner.reader is ReaderWebtoonViewController || !visible.contains(overlay.convert(rect, to: owner.view)) else { return }
        (owner.reader as? ReaderTranslationReader)?.revealTranslation(rect, in: imageView)
    }

    @objc private func toggleAll() { showAll.toggle(); render() }
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

    @objc private func showOptions() { openOptions() }

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
            // Stepping through dialogue sits on the right.
            let buttons = [allButton, listButton, translateButton, optionsButton, retryButton, closeDialogueButton,
                           previousButton, nextButton]
            let symbols = ["text.bubble", "list.number", "translate", "gearshape", "arrow.clockwise", "xmark.circle",
                           "chevron.left", "chevron.right"]
            let labels = ["Show all translations", "Dialogue list", "Translate pages in view", "Translation options",
                          "Retry translation", "Close dialogue", "Previous dialogue", "Next dialogue"]
            for (index, button) in buttons.enumerated() {
                button.setImage(UIImage(systemName: symbols[index]), for: .normal)
                button.accessibilityLabel = labels[index]
                button.heightAnchor.constraint(equalToConstant: 40).isActive = true
            }
            previousButton.addTarget(self, action: #selector(selectPrevious), for: .touchUpInside)
            nextButton.addTarget(self, action: #selector(selectNext), for: .touchUpInside)
            allButton.addTarget(self, action: #selector(toggleAll), for: .touchUpInside)
            listButton.addTarget(self, action: #selector(openList), for: .touchUpInside)
            translateButton.addTarget(self, action: #selector(translateVisible), for: .touchUpInside)
            optionsButton.addTarget(self, action: #selector(showOptions), for: .touchUpInside)
            retryButton.addTarget(self, action: #selector(retry), for: .touchUpInside)
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
        }
        accessory.isHidden = false
        owner.view.bringSubviewToFront(accessory)
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
}
