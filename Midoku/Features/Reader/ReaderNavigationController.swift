//
//  ReaderNavigationController.swift
//  Midoku (iOS)
//
//  Created by Skitty on 12/23/21.
//

import SwiftUI
import AidokuRunner

class ReaderNavigationController: UINavigationController, UIGestureRecognizerDelegate {
    let readerViewController: ReaderViewController
    let mangaInfo: MangaInfo?
    private(set) lazy var readerBackGesture = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleReaderBack(_:)))

    init(readerViewController: ReaderViewController, mangaInfo: MangaInfo? = nil) {
        self.readerViewController = readerViewController
        self.mangaInfo = mangaInfo
        super.init(rootViewController: readerViewController)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        readerBackGesture.edges = .left
        readerBackGesture.maximumNumberOfTouches = 1
        readerBackGesture.cancelsTouchesInView = false
        readerBackGesture.delaysTouchesBegan = false
        readerBackGesture.delaysTouchesEnded = false
        readerBackGesture.delegate = self
        view.addGestureRecognizer(readerBackGesture)
    }

    private var usesVerticalScrolling: Bool {
        guard let reader = topViewController as? ReaderViewController else { return false }
        // Paginated novels always turn horizontally, regardless of the manga preference.
        if reader.reader is ReaderPagedTextViewController { return false }
        return reader.reader is ReaderWebtoonViewController
            || reader.reader is ReaderTextViewController
            || [.webtoon, .continuous, .vertical].contains(reader.readingMode)
    }

    private func isReaderScrollPan(_ gesture: UIGestureRecognizer) -> Bool {
        guard let reader = topViewController as? ReaderViewController,
              reader.isViewLoaded,
              let scrollView = gesture.view as? UIScrollView,
              gesture === scrollView.panGestureRecognizer else { return false }
        return scrollView.isDescendant(of: reader.view)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Vertical pans must start immediately, including drags near the left edge.
        // The back gesture independently rejects vertical motion in shouldBegin.
        gestureRecognizer === readerBackGesture
            && usesVerticalScrolling
            && isReaderScrollPan(otherGestureRecognizer)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Only horizontal page turns compete with a horizontal back swipe. Resolve
        // that conflict per gesture; never install permanent waits on every pan.
        gestureRecognizer === readerBackGesture
            && !usesVerticalScrolling
            && isReaderScrollPan(otherGestureRecognizer)
    }

    func acceptsReaderBackTouch(at point: CGPoint, touchedView: UIView?) -> Bool {
        guard point.x >= 0, point.x <= 32,
              let reader = topViewController as? ReaderViewController,
              presentedViewController == nil, reader.presentedViewController == nil else { return false }
        if let webtoon = reader.reader as? ReaderWebtoonViewController,
           webtoon.scrollView.zoomScale > webtoon.scrollView.minimumZoomScale + 0.01 {
            return false
        }
        var candidate = touchedView
        while let current = candidate {
            if current is UIControl || current === reader.controlsView { return false }
            if let scroll = current as? UIScrollView,
               scroll.zoomScale > scroll.minimumZoomScale + 0.01 { return false }
            candidate = current.superview
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === readerBackGesture else { return true }
        return acceptsReaderBackTouch(at: touch.location(in: view), touchedView: touch.view)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === readerBackGesture, presentedViewController == nil,
              let reader = topViewController as? ReaderViewController,
              reader.presentedViewController == nil else { return false }
        return Self.shouldBeginReaderBack(velocity: readerBackGesture.velocity(in: view))
    }

    static func shouldBeginReaderBack(velocity: CGPoint) -> Bool {
        velocity.x > 0 && velocity.x > abs(velocity.y) * 1.5
    }

    static func shouldCloseReader(translation: CGPoint, velocity: CGPoint, width: CGFloat) -> Bool {
        guard translation.x > abs(translation.y) else { return false }
        return translation.x > max(80, width * 0.2) || (translation.x > 16 && velocity.x > 600)
    }

    @objc private func handleReaderBack(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard gesture.state == .ended,
              Self.shouldCloseReader(translation: gesture.translation(in: view), velocity: gesture.velocity(in: view), width: view.bounds.width)
        else { return }
        (topViewController as? ReaderViewController)?.close()
    }

    override var childForStatusBarHidden: UIViewController? {
        topViewController
    }

    override var childForStatusBarStyle: UIViewController? {
        topViewController
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        switch UserDefaults.standard.string(forKey: "Reader.orientation") {
            case "device": .all
            case "portrait": .portrait
            case "landscape": .landscape
            default: .all
        }
    }
}

struct SwiftUIReaderNavigationController: View {
    let source: AidokuRunner.Source?
    let manga: AidokuRunner.Manga
    let chapter: AidokuRunner.Chapter
    var startPage: Int?

    @State private var interfaceOrientations: UIInterfaceOrientationMask?

    init(
        source: AidokuRunner.Source?,
        manga: AidokuRunner.Manga,
        chapter: AidokuRunner.Chapter,
        startPage: Int? = nil
    ) {
        self.source = source
        self.manga = manga
        self.chapter = chapter
        self.startPage = startPage

        let interfaceOrientations: UIInterfaceOrientationMask
        switch UserDefaults.standard.string(forKey: "Reader.orientation") {
            case "device": interfaceOrientations = .all
            case "portrait": interfaceOrientations = .portrait
            case "landscape": interfaceOrientations = .landscape
            default: interfaceOrientations = .all
        }
        _interfaceOrientations = State(initialValue: interfaceOrientations)
    }

    var body: some View {
        _SwiftUIReaderNavigationController(source: source, manga: manga, chapter: chapter, startPage: startPage)
            .interfaceOrientations(interfaceOrientations)
            .onReceive(NotificationCenter.default.publisher(for: .readerOrientation)) { _ in
                switch UserDefaults.standard.string(forKey: "Reader.orientation") {
                    case "device": interfaceOrientations = .all
                    case "portrait": interfaceOrientations = .portrait
                    case "landscape": interfaceOrientations = .landscape
                    default: interfaceOrientations = .all
                }
            }
    }
}

private struct _SwiftUIReaderNavigationController: UIViewControllerRepresentable {
    let source: AidokuRunner.Source?
    let manga: AidokuRunner.Manga
    let chapter: AidokuRunner.Chapter
    var startPage: Int?

    final class Coordinator {
        var nav: ReaderNavigationController?
        var reader: ReaderViewController?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> ReaderNavigationController {
        if let nav = context.coordinator.nav { return nav }

        let reader = ReaderViewController(
            source: source,
            manga: manga,
            chapter: chapter,
            startPage: startPage
        )
        let nav = ReaderNavigationController(readerViewController: reader)
        context.coordinator.reader = reader
        context.coordinator.nav = nav
        return nav
    }

    func updateUIViewController(_ uiViewController: ReaderNavigationController, context: Context) {
        guard let reader = context.coordinator.reader else { return }

        // make a fresh reader instance if needed
        if reader.manga.key != manga.key || reader.manga.sourceKey != manga.sourceKey {
            let newReader = ReaderViewController(
                source: source,
                manga: manga,
                chapter: chapter,
                startPage: startPage
            )
            context.coordinator.reader = newReader
            uiViewController.setViewControllers([newReader], animated: false)
        } else {
            // Otherwise, update the existing reader instance
            if reader.chapter != chapter {
                reader.setChapter(chapter)
                reader.loadCurrentChapter()
            }
        }
    }
}
