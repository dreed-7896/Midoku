//
//  SourceErrorView.swift
//  Midoku
//
//  Created by Skitty on 11/19/25.
//

import AidokuRunner
import UIKit

// uikit equivalent of ErrorView: Midoku Web's error card at the top of the page
class SourceErrorView: UIView {
    var onRetry: (() async -> Void)?

    private let card = MDStateCardView()

    override init(frame: CGRect = .zero) {
        super.init(frame: frame)
        card.onAction = { [weak self] in self?.retryPressed() }
        addSubview(card)
        card.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 16),
            card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16)
        ])
        setError(nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // let touches outside the card reach the content below
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        return view === self ? nil : view
    }

    func setError(_ error: Error?) {
        card.set(
            systemImage: "exclamationmark.triangle",
            title: "Couldn’t load",
            detail: error?.midokuDescription() ?? NSLocalizedString("UNKNOWN_ERROR"),
            tone: .error
        )
        var showRetry = false
        if onRetry != nil, let error = error as? SourceError {
            if case .unimplemented = error {} else { showRetry = true }
        }
        card.setAction(showRetry ? NSLocalizedString("RETRY") : nil)
    }

    func show(animated: Bool = true) {
        guard isHidden else { return }
        if animated {
            alpha = 0
            isHidden = false
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                self.alpha = 1
            }
        } else {
            isHidden = false
        }
    }

    func hide(animated: Bool = true) {
        guard !isHidden else { return }
        if animated {
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                self.alpha = 0
            } completion: { _ in
                self.isHidden = true
                self.alpha = 1
            }
        } else {
            isHidden = true
        }
    }

    private func retryPressed() {
        guard let onRetry else { return }
        card.setBusy(true)
        Task {
            await onRetry()
            card.setBusy(false)
            card.setAction(NSLocalizedString("RETRY"))
        }
    }
}
