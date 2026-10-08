//
//  ReaderNavigationController.swift
//  Midoku (iOS)
//
//  Created by Skitty on 12/23/21.
//

import SwiftUI
import AidokuRunner

class ReaderNavigationController: UINavigationController {
    let readerViewController: ReaderViewController
    let mangaInfo: MangaInfo?

    init(readerViewController: ReaderViewController, mangaInfo: MangaInfo? = nil) {
        self.readerViewController = readerViewController
        self.mangaInfo = mangaInfo
        super.init(rootViewController: readerViewController)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var childForStatusBarHidden: UIViewController? { topViewController }
    override var childForStatusBarStyle: UIViewController? { topViewController }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        switch UserDefaults.standard.string(forKey: "Reader.orientation") {
        case "portrait": .portrait
        case "landscape": .landscape
        default: .all
        }
    }
}

/// Use UIKit's existing pop recognizer and transition; no reader-owned swipe recognizer.
@MainActor
final class ReaderPopGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    weak var reader: ReaderViewController?
    private weak var navigation: UINavigationController?
    private weak var originalDelegate: (any UIGestureRecognizerDelegate)?
    private var originalContentPopEnabled = false
    private var originalPopEnabled = false

    init(reader: ReaderViewController) { self.reader = reader }

    func install(on navigation: UINavigationController) {
        guard self.navigation == nil else { return }
        self.navigation = navigation
        originalDelegate = navigation.interactivePopGestureRecognizer?.delegate
        originalPopEnabled = navigation.interactivePopGestureRecognizer?.isEnabled ?? false
        navigation.interactivePopGestureRecognizer?.delegate = self
        navigation.interactivePopGestureRecognizer?.isEnabled = true
        if #available(iOS 26.0, *) {
            originalContentPopEnabled = navigation.interactiveContentPopGestureRecognizer?.isEnabled ?? false
            // Edge swipe keeps horizontal page turns and zoomed panels independent.
            navigation.interactiveContentPopGestureRecognizer?.isEnabled = false
        }
    }

    func restore() {
        guard let navigation else { return }
        if navigation.interactivePopGestureRecognizer?.delegate === self {
            navigation.interactivePopGestureRecognizer?.delegate = originalDelegate
            navigation.interactivePopGestureRecognizer?.isEnabled = originalPopEnabled
        }
        if #available(iOS 26.0, *) {
            navigation.interactiveContentPopGestureRecognizer?.isEnabled = originalContentPopEnabled
        }
        self.navigation = nil
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let navigation, navigation.viewControllers.count > 1,
              navigation.transitionCoordinator == nil, navigation.presentedViewController == nil,
              let reader, reader.presentedViewController == nil else { return false }
        if let webtoon = reader.reader as? ReaderWebtoonViewController,
           webtoon.scrollView.zoomScale > webtoon.scrollView.minimumZoomScale + 0.01 { return false }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var candidate = touch.view
        while let current = candidate {
            if current is UIControl || current === reader?.controlsView { return false }
            if let scroll = current as? UIScrollView, scroll.zoomScale > scroll.minimumZoomScale + 0.01 { return false }
            candidate = current.superview
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        guard let reader, let scroll = other.view as? UIScrollView,
              other === scroll.panGestureRecognizer, scroll.isDescendant(of: reader.view) else { return false }
        return reader.reader is ReaderWebtoonViewController || reader.reader is ReaderTextViewController
            || [.webtoon, .continuous, .vertical].contains(reader.readingMode)
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
