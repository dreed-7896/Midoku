//
//  ReaderToolbarView.swift
//  Midoku (iOS)
//
//  Created by Skitty on 8/15/22.
//

import Combine
import UIKit

class ReaderToolbarView: UIView {
    var currentPageValue: Int? {
        didSet {
            if oldValue != currentPageValue {
                let feedbackGenerator = UISelectionFeedbackGenerator()
                feedbackGenerator.selectionChanged()
            }
        }
    }
    var currentPage: Int? {
        didSet { updatePageLabels() }
    }
    var totalPages: Int? {
        didSet { updatePageLabels() }
    }

    let sliderView = ReaderSliderView()
    let previousChapterButton = UIButton(type: .system)
    let nextChapterButton = UIButton(type: .system)
    private let incognitoModeLabel = UILabel()
    private let currentPageLabel = UILabel()
    private let pagesLeftLabel = UILabel()

    private var cancellables: [AnyCancellable] = []

    init() {
        super.init(frame: .zero)
        configure()
        constrain()
        observe()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure() {
        ReaderBarButton.style(previousChapterButton, symbol: "backward.end.fill")
        previousChapterButton.accessibilityLabel = "Previous chapter"
        ReaderBarButton.style(nextChapterButton, symbol: "forward.end.fill")
        nextChapterButton.accessibilityLabel = "Next chapter"
        addSubview(previousChapterButton)
        addSubview(nextChapterButton)
        incognitoModeLabel.font = MDFont.mono(11, .semibold) ?? .systemFont(ofSize: 11, weight: .medium)
        incognitoModeLabel.textColor = MDColor.accent
        incognitoModeLabel.textAlignment = .left
        incognitoModeLabel.isHidden = !AppSettings.general.incognitoMode.get()
        addSubview(incognitoModeLabel)

        currentPageLabel.font = MDFont.mono(12, .semibold) ?? .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        currentPageLabel.textColor = MDColor.text2
        currentPageLabel.textAlignment = .center
        currentPageLabel.sizeToFit()
        addSubview(currentPageLabel)

        pagesLeftLabel.font = MDFont.mono(11, .regular) ?? .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        pagesLeftLabel.textColor = MDColor.text3
        pagesLeftLabel.textAlignment = .right
        addSubview(pagesLeftLabel)

        sliderView.semanticContentAttribute = .playback // for rtl languages
        addSubview(sliderView)
    }

    func constrain() {
        incognitoModeLabel.translatesAutoresizingMaskIntoConstraints = false
        currentPageLabel.translatesAutoresizingMaskIntoConstraints = false
        pagesLeftLabel.translatesAutoresizingMaskIntoConstraints = false
        sliderView.translatesAutoresizingMaskIntoConstraints = false
        previousChapterButton.translatesAutoresizingMaskIntoConstraints = false
        nextChapterButton.translatesAutoresizingMaskIntoConstraints = false

        // Page details sit on their own row above the slider instead of underneath it.
        NSLayoutConstraint.activate([
            currentPageLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            currentPageLabel.topAnchor.constraint(equalTo: topAnchor),

            incognitoModeLabel.leadingAnchor.constraint(equalTo: sliderView.leadingAnchor),
            incognitoModeLabel.centerYAnchor.constraint(equalTo: currentPageLabel.centerYAnchor),
            incognitoModeLabel.trailingAnchor.constraint(lessThanOrEqualTo: currentPageLabel.leadingAnchor, constant: -8),

            pagesLeftLabel.trailingAnchor.constraint(equalTo: sliderView.trailingAnchor),
            pagesLeftLabel.centerYAnchor.constraint(equalTo: currentPageLabel.centerYAnchor),
            pagesLeftLabel.leadingAnchor.constraint(greaterThanOrEqualTo: currentPageLabel.trailingAnchor, constant: 8),

            previousChapterButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            previousChapterButton.bottomAnchor.constraint(equalTo: bottomAnchor),

            nextChapterButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            nextChapterButton.bottomAnchor.constraint(equalTo: bottomAnchor),

            sliderView.heightAnchor.constraint(equalToConstant: 44),
            sliderView.centerYAnchor.constraint(equalTo: previousChapterButton.centerYAnchor),
            sliderView.leadingAnchor.constraint(equalTo: previousChapterButton.trailingAnchor, constant: 12),
            sliderView.trailingAnchor.constraint(equalTo: nextChapterButton.leadingAnchor, constant: -12)
        ])
    }

    func observe() {
        NotificationCenter.default.publisher(for: .init(AppSettings.general.incognitoMode.key))
            .sink { [weak self] _ in
                self?.incognitoModeLabel.isHidden = !AppSettings.general.incognitoMode.get()
            }
            .store(in: &cancellables)
    }

    // allow slider thumb to be touched outside bounds
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled else { return nil }
        if sliderView.frame.contains(point) { return sliderView }
        for subview in subviews where subview is ReaderSliderView {
            if subview.subviews.contains(where: { $0.bounds.contains(convert(point, to: $0)) }) {
                return subview
            }
        }
        return super.hitTest(point, with: event)
    }

    func displayPage(_ page: Int) {
        guard let totalPages = totalPages else {
            return
        }
        var page = page
        if page > totalPages {
            page = totalPages
        } else if page < 1 {
            page = 1
        }
        currentPageLabel.text = "\(page) / \(totalPages)"
        currentPageValue = page
    }

    func updatePageLabels() {
        guard var currentPage = currentPage, let totalPages = totalPages else {
            currentPageLabel.text = nil
            pagesLeftLabel.text = nil
            return
        }

        if currentPage > totalPages {
            currentPage = totalPages
        } else if currentPage < 1 {
            currentPage = 1
        }
        let pagesLeft = totalPages - currentPage
        currentPageLabel.text = "\(currentPage) / \(totalPages)"
        sliderView.accessibilityValue = currentPageLabel.text
        if pagesLeft < 1 {
            pagesLeftLabel.text = nil
        } else {
            pagesLeftLabel.text = pagesLeft == 1
                ? NSLocalizedString("ONE_PAGE_LEFT")
                : String(format: NSLocalizedString("%i_PAGES_LEFT"), pagesLeft)
        }
        incognitoModeLabel.text = NSLocalizedString("INCOGNITO_MODE")
    }

    func updateSliderPosition() {
        guard let currentPage = currentPage, let totalPages = totalPages else { return }
        sliderView.move(toValue: CGFloat(currentPage - 1) / max(CGFloat(totalPages - 1), 1))
    }
}
