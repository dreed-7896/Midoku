//
//  GIFImageNode.swift
//  Midoku
//
//  Created by Skitty on 6/23/25.
//

import AsyncDisplayKit
import Gifu
import VisionKit

// Static panels use UIImageView's normal display path. Gifu's GIFImageView
// creates an animator and reassigns the image from every layer display callback,
// even for JPEG/PNG panels. Only opt into that work for an actual animated GIF.
final class ReaderImageView: UIImageView, GIFAnimatable {
    var animator: Animator?

    func displayGIF(_ data: Data) {
        if animator == nil { animator = Animator(withDelegate: self) }
        animate(withGIFData: data)
    }

    func clearGIF() {
        // Releasing the animator also releases its frame buffer and display link.
        animator = nil
    }

    override func display(_ layer: CALayer) {
        if UIImageView.instancesRespond(to: #selector(display(_:))) {
            super.display(layer)
        }
        if animator != nil { updateImageIfNeeded() }
    }
}

class GIFImageNode: ASControlNode {
    var imageView: ReaderImageView?
    var animatedData: Data?
    var storedInteractions: [UIInteraction] = []

    override var contentMode: UIView.ContentMode {
        didSet {
            imageView?.contentMode = contentMode
        }
    }

    var image: UIImage? {
        didSet {
            guard image !== oldValue else { return }
            Task { @MainActor in
                imageView?.image = image
            }
        }
    }

    override var isUserInteractionEnabled: Bool {
        didSet {
            imageView?.isUserInteractionEnabled = isUserInteractionEnabled
        }
    }

    @available(iOS 16.0, *)
    var imageAnalaysisInteraction: ImageAnalysisInteraction? {
        imageView?.interactions.first(where: { $0 is ImageAnalysisInteraction }) as? ImageAnalysisInteraction
    }

    override init() {
        super.init()

        setViewBlock { [weak self] in
            let gifView = ReaderImageView()
            gifView.image = self?.image
            gifView.isUserInteractionEnabled = true
            if let contentMode = self?.contentMode {
                gifView.contentMode = contentMode
            }
            if let data = self?.animatedData {
                gifView.displayGIF(data)
                self?.animatedData = nil
            }
            if let storedInteractions = self?.storedInteractions {
                storedInteractions.forEach {
                    gifView.addInteraction($0)
                }
                self?.storedInteractions = []
            }
            self?.imageView = gifView
            return gifView
        }
    }

    func animate(withGIFData data: Data) {
        if let imageView {
            Task { @MainActor in
                imageView.displayGIF(data)
            }
        } else {
            animatedData = data
        }
    }

    func reset() {
        image = nil
        animatedData = nil

        Task { @MainActor [weak imageView] in
            imageView?.clearGIF()
            imageView?.image = nil
        }
    }

    @MainActor
    func addInteraction(_ interaction: UIInteraction) {
        if let imageView {
            imageView.addInteraction(interaction)
        } else {
            storedInteractions.append(interaction)
        }
    }

    @MainActor
    @available(iOS 16.0, *)
    func removeImageAnalysisInteraction() {
        guard
            let imageView,
            let interaction = imageView.interactions.first(where: { $0 is ImageAnalysisInteraction })
        else {
            return
        }
        imageView.removeInteraction(interaction)
    }
}
