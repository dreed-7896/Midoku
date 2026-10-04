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
        needsRebuild = false
        preparedSize = boundsSize

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
                UIView.performWithoutAnimation {
                    let newContentSize = collectionViewContentSize
                    let contentOffsetX = collectionView.contentOffset.x + (newContentSize.width - oldContentSize.width)
                    let contentOffsetY = collectionView.contentOffset.y + (newContentSize.height - oldContentSize.height)
                    let newOffset = CGPoint(x: contentOffsetX, y: contentOffsetY)
                    collectionView.contentOffset = newOffset
                }
            }
            contentSizeBeforeInsertingAbove = nil
            isInsertingCellsAbove = false
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
