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
    var onDismissed: (() -> Void)?
    private var interactiveDismissal: UIPercentDrivenInteractiveTransition?
    private var dismissVertically = false
    private(set) lazy var readerBackGesture = UIPanGestureRecognizer(target: self, action: #selector(handleReaderBack(_:)))

    init(readerViewController: ReaderViewController, mangaInfo: MangaInfo? = nil) {
        self.readerViewController = readerViewController
        self.mangaInfo = mangaInfo
        super.init(rootViewController: readerViewController)
        modalPresentationStyle = .fullScreen
        transitioningDelegate = self
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        readerBackGesture.maximumNumberOfTouches = 1
        readerBackGesture.delegate = self
        view.addGestureRecognizer(readerBackGesture)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || presentingViewController == nil { onDismissed?() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        prioritizeReaderBackGesture()
    }

    func prioritizeReaderBackGesture() {
        guard isViewLoaded, let reader = topViewController as? ReaderViewController, reader.isViewLoaded else { return }
        func visit(_ view: UIView) {
            for gesture in view.gestureRecognizers ?? [] where gesture is UIPanGestureRecognizer && gesture !== readerBackGesture {
                gesture.require(toFail: readerBackGesture)
            }
            for child in view.subviews { visit(child) }
        }
        visit(reader.view)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === readerBackGesture, presentedViewController == nil,
              let reader = topViewController as? ReaderViewController,
              reader.presentedViewController == nil else { return false }
        let velocity = readerBackGesture.velocity(in: view)
        let translation = readerBackGesture.translation(in: view)
        let point = readerBackGesture.location(in: view)
        let origin = CGPoint(x: point.x - translation.x, y: point.y - translation.y)
        func zoomed(in view: UIView) -> Bool {
            if let scroll = view as? UIScrollView, scroll.zoomScale > scroll.minimumZoomScale + 0.01 { return true }
            return view.subviews.contains { !$0.isHidden && zoomed(in: $0) }
        }
        guard !zoomed(in: reader.view) else { return false }
        dismissVertically = velocity.y > abs(velocity.x)
        if dismissVertically {
            let scrollingVertically = reader.reader is ReaderWebtoonViewController
                || reader.reader is ReaderTextViewController || reader.readingMode == .vertical
            return velocity.y > 0 && (!scrollingVertically || origin.y < view.safeAreaInsets.top + 96)
        }
        return origin.x < 80 && velocity.x > 0 && velocity.x > abs(velocity.y)
    }

    static func shouldCloseReader(translation: CGPoint, velocity: CGPoint, width: CGFloat) -> Bool {
        translation.x > max(80, width * 0.2) || (translation.x > 16 && velocity.x > 600)
    }

    @objc private func handleReaderBack(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)
        let distance = dismissVertically ? translation.y : translation.x
        let extent = dismissVertically ? view.bounds.height : view.bounds.width
        let progress = max(0, min(1, distance / max(1, extent)))
        switch gesture.state {
        case .began:
            interactiveDismissal = UIPercentDrivenInteractiveTransition()
            interactiveDismissal?.completionCurve = .easeOut
            dismiss(animated: true)
        case .changed:
            interactiveDismissal?.update(progress)
        case .ended:
            let finish = dismissVertically
                ? distance > max(100, extent * 0.18) || (distance > 16 && velocity.y > 600)
                : Self.shouldCloseReader(translation: translation, velocity: velocity, width: extent)
            if finish { interactiveDismissal?.finish() } else { interactiveDismissal?.cancel() }
            interactiveDismissal = nil
        case .cancelled, .failed:
            interactiveDismissal?.cancel()
            interactiveDismissal = nil
        default: break
        }
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

extension ReaderNavigationController: UIViewControllerTransitioningDelegate {
    func animationController(forPresented presented: UIViewController, presenting: UIViewController,
                             source: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        ReaderDismissAnimator(presenting: true, vertical: false)
    }

    func animationController(forDismissed dismissed: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        ReaderDismissAnimator(presenting: false, vertical: interactiveDismissal != nil && dismissVertically)
    }

    func interactionControllerForDismissal(using animator: any UIViewControllerAnimatedTransitioning)
        -> (any UIViewControllerInteractiveTransitioning)? { interactiveDismissal }
}

private final class ReaderDismissAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    let presenting: Bool
    let vertical: Bool
    init(presenting: Bool, vertical: Bool) { self.presenting = presenting; self.vertical = vertical; super.init() }
    func transitionDuration(using context: (any UIViewControllerContextTransitioning)?) -> TimeInterval { 0.3 }
    func animateTransition(using context: any UIViewControllerContextTransitioning) {
        guard let from = context.view(forKey: .from), let to = context.view(forKey: .to) else {
            context.completeTransition(false); return
        }
        let container = context.containerView
        if let controller = context.viewController(forKey: .to) { to.frame = context.finalFrame(for: controller) }
        if presenting {
            container.addSubview(to)
            to.alpha = 0
        } else {
            container.insertSubview(to, belowSubview: from)
        }
        UIView.animate(withDuration: transitionDuration(using: context), delay: 0, options: .curveEaseOut) {
            if self.presenting { to.alpha = 1 }
            else {
                from.transform = CGAffineTransform(translationX: self.vertical ? 0 : container.bounds.width,
                    y: self.vertical ? container.bounds.height : 0)
            }
        } completion: { _ in
            from.transform = .identity
            to.alpha = 1
            context.completeTransition(!context.transitionWasCancelled)
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
