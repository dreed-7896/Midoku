//
//  ReaderSliderView.swift
//  Midoku (iOS)
//
//  Created by Skitty on 1/20/22.
//

import UIKit

class ReaderSliderView: UIControl {
    enum SliderDirection {
        case forward
        case backward
    }

    var direction: SliderDirection = .forward {
        didSet {
            thumbPositionConstraint?.isActive = false
            trackPositionConstraint?.isActive = false
            if direction == .forward {
                thumbPositionConstraint = thumbView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -10)
                trackPositionConstraint = progressedTrackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5)
            } else {
                thumbPositionConstraint = thumbView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 10)
                trackPositionConstraint = progressedTrackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5)
            }
            thumbPositionConstraint?.isActive = true
            trackPositionConstraint?.isActive = true
        }
    }

    var minimumValue: CGFloat = 0
    var maximumValue: CGFloat = 1
    var currentValue: CGFloat = 0 {
        didSet {
            let boundedValue = boundValue(
                currentValue,
                toLowerValue: minimumValue,
                upperValue: maximumValue
            )
            if currentValue != boundedValue {
                currentValue = boundedValue
                return
            }
            updateLayerFrames()
        }
    }

    private lazy var trackView = {
        let trackView = UIView()
        trackView.backgroundColor = MDColor.line2
        trackView.layer.cornerRadius = 0
        trackView.isUserInteractionEnabled = false
        return trackView
    }()
    private lazy var progressedTrackView = {
        let progressedTrackView = UIView()
        progressedTrackView.backgroundColor = MDColor.accent
        progressedTrackView.layer.cornerRadius = 0
        progressedTrackView.isUserInteractionEnabled = false
        return progressedTrackView
    }()
    private lazy var thumbView = {
        let thumbView = UIView()
        thumbView.isUserInteractionEnabled = false
        return thumbView
    }()

    private lazy var grabberView: UIView = {
        let grabberView: UIView
        if #available(iOS 26.0, *) {
            // same aspect ratio as a UISlider knob
            grabberView = {
                let grabberView = LiquidLensView(frame: .init(x: 0, y: 0, width: 18.5, height: 12))
                grabberView.restingBackgroundColor = .white
                return grabberView as UIView
            }()
            grabberView.layer.shadowPath = UIBezierPath(roundedRect: grabberView.bounds, cornerRadius: 6).cgPath
        } else {
            grabberView = UIView(frame: .init(x: 0, y: 0, width: 10, height: 10))
            grabberView.backgroundColor = .white
            grabberView.layer.shadowPath = UIBezierPath(roundedRect: grabberView.bounds, cornerRadius: 5).cgPath
        }
        grabberView.layer.shadowRadius = 1.5
        grabberView.layer.shadowOffset = CGSize(width: 0, height: 1)
        grabberView.layer.shadowColor = UIColor.black.cgColor
        grabberView.layer.shadowOpacity = 0.1
        grabberView.layer.cornerRadius = grabberView.frame.height / 2
        return grabberView
    }()

    private var trackWidthConstraint: NSLayoutConstraint?
    private var trackPositionConstraint: NSLayoutConstraint?
    private var thumbPositionConstraint: NSLayoutConstraint?


    override var frame: CGRect {
        didSet {
            updateLayerFrames()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
        constrain()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure() {
        isAccessibilityElement = true
        accessibilityLabel = "Page"
        accessibilityTraits = .adjustable
        thumbView.addSubview(grabberView)

        addSubview(trackView)
        addSubview(progressedTrackView)
        addSubview(thumbView)
    }

    func constrain() {
        trackView.translatesAutoresizingMaskIntoConstraints = false
        progressedTrackView.translatesAutoresizingMaskIntoConstraints = false
        thumbView.translatesAutoresizingMaskIntoConstraints = false
        grabberView.translatesAutoresizingMaskIntoConstraints = false

        trackWidthConstraint = progressedTrackView.widthAnchor.constraint(equalToConstant: 5)
        trackWidthConstraint?.isActive = true
        trackPositionConstraint = progressedTrackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5)
        trackPositionConstraint?.isActive = true
        thumbPositionConstraint = thumbView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -10)
        thumbPositionConstraint?.isActive = true

        NSLayoutConstraint.activate([
            trackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            trackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            trackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            trackView.heightAnchor.constraint(equalToConstant: 3),

            progressedTrackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            progressedTrackView.heightAnchor.constraint(equalToConstant: 3),

            thumbView.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbView.heightAnchor.constraint(equalToConstant: 30),
            thumbView.widthAnchor.constraint(equalToConstant: 30),

            grabberView.centerXAnchor.constraint(equalTo: thumbView.centerXAnchor),
            grabberView.centerYAnchor.constraint(equalTo: thumbView.centerYAnchor),
            grabberView.heightAnchor.constraint(equalToConstant: grabberView.bounds.height),
            grabberView.widthAnchor.constraint(equalToConstant: grabberView.bounds.width)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateLayerFrames()
    }

    override func tintColorDidChange() {
        progressedTrackView.backgroundColor = tintColor
    }

    private func updateLayerFrames() {
        guard trackView.frame.size != .zero else { return }
        let position = positionForValue(currentValue)
        if direction == .forward {
            trackWidthConstraint?.constant = position - trackView.frame.origin.x
            thumbPositionConstraint?.constant =  position - thumbView.bounds.width / 2
        } else {
            trackWidthConstraint?.constant = trackView.frame.maxX - position
            thumbPositionConstraint?.constant = position - bounds.width + thumbView.bounds.width / 2
        }
    }
}

extension ReaderSliderView {
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard isEnabled else { return false }
        thumbView.tag = 1
        seek(to: touch.location(in: self))
        UIView.animate(withDuration: 0.2) {
            self.grabberView.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
            if #available(iOS 26.0, *) {
                (self.grabberView as? LiquidLensView)?.setLifted(true, animated: true)
            }
        }
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        seek(to: touch.location(in: self))
        return true
    }

    func value(at point: CGPoint) -> CGFloat {
        let width = max(1, bounds.width - 10)
        let fraction = min(1, max(0, (point.x - 5) / width))
        let directed = direction == .forward ? fraction : 1 - fraction
        return minimumValue + directed * (maximumValue - minimumValue)
    }

    private func seek(to point: CGPoint) {
        currentValue = value(at: point)
        sendActions(for: .valueChanged)
    }

    override func accessibilityIncrement() { adjustAccessibility(by: 0.05) }
    override func accessibilityDecrement() { adjustAccessibility(by: -0.05) }
    private func adjustAccessibility(by fraction: CGFloat) {
        currentValue += fraction * (maximumValue - minimumValue)
        sendActions(for: .valueChanged)
        sendActions(for: .editingDidEnd)
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        thumbView.tag = 0
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseInOut) {
            self.grabberView.transform = .identity
            if #available(iOS 26.0, *) {
                (self.grabberView as? LiquidLensView)?.setLifted(false, animated: true)
            }
        }
        sendActions(for: .editingDidEnd)
    }

    override func cancelTracking(with event: UIEvent?) {
        endTracking(nil, with: event)
    }
}

extension ReaderSliderView {
    func move(toValue value: CGFloat) {
        currentValue = value
    }

    private func positionForValue(_ value: CGFloat) -> CGFloat {
        let range = maximumValue - minimumValue
        let fraction = range > 0 ? (value - minimumValue) / range : 0
        return trackView.frame.minX + trackView.bounds.width * (direction == .forward ? fraction : 1 - fraction)
    }

    private func boundValue(_ value: CGFloat, toLowerValue lowerValue: CGFloat, upperValue: CGFloat) -> CGFloat {
        min(max(value, lowerValue), upperValue)
    }
}
