//
//  VerticalContentOffsetPreservingLayout.swift
//  Midoku (iOS)
//
//  Created by Skitty on 3/1/23.
//  Thanks to Mantton (https://github.com/Mantton) for this.
//

import UIKit
import AsyncDisplayKit

class VerticalContentOffsetPreservingLayout: UICollectionViewFlowLayout {

    var isInsertingCellsAbove: Bool = false {
        didSet {
            if isInsertingCellsAbove {
                contentSizeBeforeInsertingAbove = collectionViewContentSize
            }
        }
    }

    var spacing: CGFloat {
        get { minimumLineSpacing }
        set { minimumLineSpacing = newValue }
    }

    private var contentSizeBeforeInsertingAbove: CGSize?
    private var scale: CGFloat = 1

    private var contentSize = CGSize.zero
    override var collectionViewContentSize: CGSize {
        contentSize
    }

    private var currentAttributes: [IndexPath: UICollectionViewLayoutAttributes] = [:]
    private var orderedAttributes: [UICollectionViewLayoutAttributes] = []
    private var needsRebuild = true
    private var preparedSize = CGSize.zero
    private var preparedScale: CGFloat = 1
    private var pendingOffsetAdjustment: CGFloat = 0

    // The overlay scroll view owns momentum. Geometry updates report a delta;
    // they must not set its position from the collection view's mirrored offset.
    var onGeometryChange: (() -> Void)?

    func consumeOffsetAdjustment() -> CGFloat {
        defer { pendingOffsetAdjustment = 0 }
        return pendingOffsetAdjustment
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        // Moving the viewport doesn't change any page geometry.
        newBounds.size != collectionView?.bounds.size
    }

    override func invalidateLayout() {
        needsRebuild = true
        super.invalidateLayout()
    }

    override func invalidateLayout(with context: UICollectionViewLayoutInvalidationContext) {
        needsRebuild = true
        super.invalidateLayout(with: context)
    }

    override init() {
        super.init()
        scrollDirection = .vertical
        minimumInteritemSpacing = 0
        minimumLineSpacing = 0
        sectionInset = .zero
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepare() {
        guard let collectionView else { return }
        let boundsSize = collectionView.bounds.size
        guard needsRebuild || preparedSize != boundsSize else { return }
        let oldContentSize = contentSize
        let anchor: (indexPath: IndexPath, minY: CGFloat)?
        if !isInsertingCellsAbove, preparedSize == boundsSize, preparedScale == scale {
            let index = firstAttributeIndex(endingAfter: collectionView.contentOffset.y + pendingOffsetAdjustment)
            if index < orderedAttributes.count {
                let attributes = orderedAttributes[index]
                anchor = (attributes.indexPath, attributes.frame.minY)
            } else {
                anchor = nil
            }
        } else {
            anchor = nil
        }
        needsRebuild = false
        preparedSize = boundsSize
        preparedScale = scale

        // Rebuild only after a page size, chapter, viewport size or zoom change.
        currentAttributes.removeAll(keepingCapacity: true)
        orderedAttributes.removeAll(keepingCapacity: true)

        var origin: CGFloat = 0
        let width = collectionView.bounds.size.width

        for section in 0..<collectionView.numberOfSections {
            for itemIndex in 0..<collectionView.numberOfItems(inSection: section) {
                let indexPath = IndexPath(item: itemIndex, section: section)
                let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)

                let size = CGSize(width: width, height: getHeight(for: indexPath))
                attributes.frame = CGRect(origin: CGPoint(x: 0, y: origin), size: size)
                currentAttributes[indexPath] = attributes
                orderedAttributes.append(attributes)

                origin += attributes.frame.size.height + minimumLineSpacing
            }
        }

        // scale for zoom
        let size = CGSize(width: width, height: origin)
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        contentSize = size.applying(transform)

        if scale != 1 {
            // adjust cells for zoom
            for section in 0..<collectionView.numberOfSections {
                for itemIndex in 0..<collectionView.numberOfItems(inSection: section) {
                    let indexPath = IndexPath(item: itemIndex, section: section)
                    if let origFrame = currentAttributes[indexPath]?.frame {
                        let frame = CGRect(
                            origin: CGPoint(
                                x: origFrame.origin.x / size.width * contentSize.width,
                                y: origFrame.origin.y / origin * contentSize.height
                            ),
                            size: origFrame.size.applying(transform)
                        )
                        // setting frame without transform doesn't scale content,
                        // and setting frame with transform messes up the scale
                        currentAttributes[indexPath]?.transform = transform
                        currentAttributes[indexPath]?.center = CGPoint(
                            x: frame.origin.x + frame.width / 2,
                            y: frame.origin.y + frame.height / 2
                        )
                    }
                }
            }
        }

        // preserve offset when inserting cells above
        if isInsertingCellsAbove {
            if let oldContentSize = contentSizeBeforeInsertingAbove {
                pendingOffsetAdjustment += contentSize.height - oldContentSize.height
            }
            contentSizeBeforeInsertingAbove = nil
            isInsertingCellsAbove = false
        } else if let anchor, let attributes = currentAttributes[anchor.indexPath] {
            // Only height changes above the viewport move the reading position.
            // Images loading below it must never contribute to this correction.
            pendingOffsetAdjustment += attributes.frame.minY - anchor.minY
        }
        if contentSize != oldContentSize || pendingOffsetAdjustment != 0 {
            onGeometryChange?()
        }
    }

    func getHeight(for indexPath: IndexPath) -> CGFloat {
        guard
            let collectionView = collectionView as? ASCollectionView,
            let collectionNode = collectionView.collectionNode,
            let node = collectionNode.nodeForItem(at: indexPath) as? HeightQueryable
        else {
            return 0
        }
        return node.getHeight(for: collectionView.bounds.size)
    }

    func getHeightFor(section: Int, range: Range<Int>? = nil) -> CGFloat {
        var height: CGFloat = 0
        let range = range ?? 0..<(collectionView?.numberOfItems(inSection: section) ?? 0)
        for idx in range {
            let indexPath = IndexPath(item: idx, section: section)
            let attributes = currentAttributes[indexPath]
            height += attributes?.frame.height ?? 0
        }
        return height * scale
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        currentAttributes[indexPath]
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        // Pages are vertically ordered. Binary search skips all preceding chapters
        // instead of scanning the entire reader on every display/preload query.
        var index = firstAttributeIndex(endingAfter: rect.minY)
        var result: [UICollectionViewLayoutAttributes] = []
        while index < orderedAttributes.count {
            let attributes = orderedAttributes[index]
            if attributes.frame.minY > rect.maxY { break }
            if attributes.frame.intersects(rect) { result.append(attributes) }
            index += 1
        }
        return result
    }

    func indexPath(at point: CGPoint) -> IndexPath? {
        let index = firstAttributeIndex(endingAfter: point.y)
        guard index < orderedAttributes.count else { return nil }
        let attributes = orderedAttributes[index]
        return attributes.frame.contains(point) ? attributes.indexPath : nil
    }

    private func firstAttributeIndex(endingAfter y: CGFloat) -> Int {
        var lower = 0
        var upper = orderedAttributes.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if orderedAttributes[middle].frame.maxY <= y {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

}

// MARK: - Zoom Support
extension VerticalContentOffsetPreservingLayout: @MainActor ZoomableLayoutProtocol {
    func getScale() -> CGFloat {
        scale
    }

    func setScale(_ scale: CGFloat) {
        guard self.scale != scale else { return }
        self.scale = scale
        invalidateLayout()
    }
}
