import Foundation

/// A dialogue and its position in the displayed image. Bounds use a top-left, unit coordinate space.
struct TranslationRegion: Identifiable, Equatable {
    let id: Int
    let imageIndex: Int
    let sourceText: String
    let bounds: CGRect

    func rect(in size: CGSize) -> CGRect {
        CGRect(x: bounds.minX * size.width, y: bounds.minY * size.height,
               width: bounds.width * size.width, height: bounds.height * size.height)
    }
}

@available(iOS 18.0, *)
enum TranslationRegionBuilder {
    private struct Block {
        let indices: [Int]
        let bounds: CGRect
    }

    static func build(observations: [TextRecognizer.OCRObservation], imageSize: CGSize,
                      imageIndex: Int, webtoon: Bool) -> [TranslationRegion] {
        guard imageSize.width > 0, imageSize.height > 0 else { return [] }
        // Compare distances in image points, not normalized X/Y units (especially for tall webtoons).
        let observations = observations.map { observation in
            TextRecognizer.OCRObservation(
                text: observation.text,
                boundingRect: CGRect(x: observation.boundingRect.minX * imageSize.width,
                                     y: observation.boundingRect.minY * imageSize.height,
                                     width: observation.boundingRect.width * imageSize.width,
                                     height: observation.boundingRect.height * imageSize.height),
                direction: observation.direction, confidence: observation.confidence, characters: []
            )
        }
        // Group by line/column thickness instead of the length of a whole sentence. This avoids
        // joining separate bubbles just because they contain long lines of text.
        var remaining = Set(observations.indices)
        var blocks: [Block] = []
        while let seed = remaining.min() {
            remaining.remove(seed)
            var indices = [seed]
            var cursor = 0
            while cursor < indices.count {
                let current = indices[cursor]
                let neighborIndices = remaining.filter { neighbors(observations[current], observations[$0]) }.sorted()
                indices.append(contentsOf: neighborIndices)
                remaining.subtract(neighborIndices)
                cursor += 1
            }
            let bounds = indices.reduce(CGRect.null) { $0.union(observations[$1].boundingRect) }
            if !bounds.isNull, !bounds.isEmpty {
                blocks.append(Block(indices: indices, bounds: bounds))
            }
        }

        // Form rows first, then sort within each row. A pairwise Y tolerance in a sort comparator
        // is not transitive and can give unstable numbering on irregular manga layouts.
        let byHeight = blocks.sorted {
            if $0.bounds.maxY != $1.bounds.maxY { return $0.bounds.maxY > $1.bounds.maxY }
            return $0.bounds.maxX > $1.bounds.maxX
        }
        var rows: [[Block]] = []
        for block in byHeight {
            if !webtoon, let last = rows.last, let first = last.first,
               abs(first.bounds.maxY - block.bounds.maxY) < min(first.bounds.height, block.bounds.height) * 0.45 {
                rows[rows.count - 1].append(block)
            } else {
                rows.append([block])
            }
        }
        let ordered = rows.flatMap { row in row.sorted { $0.bounds.midX > $1.bounds.midX } }
        return ordered.compactMap { block in
            let vertical = block.indices.filter { isVertical(observations[$0]) }.count > block.indices.count / 2
            let lines = orderedIndices(block.indices, observations: observations, vertical: vertical)
            let text = lines.map { observations[$0].text }.joined(separator: vertical ? "" : " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.range(of: "[\\p{Han}\\p{Hiragana}\\p{Katakana}]", options: .regularExpression) != nil else { return nil }
            let box = block.bounds.intersection(CGRect(origin: .zero, size: imageSize))
            guard !box.isNull, !box.isEmpty else { return nil }
            return TranslationRegion(
                id: 0, imageIndex: imageIndex, sourceText: text,
                bounds: CGRect(x: box.minX / imageSize.width, y: 1 - box.maxY / imageSize.height,
                               width: box.width / imageSize.width, height: box.height / imageSize.height)
            )
        }
    }

    private static func orderedIndices(_ indices: [Int], observations: [TextRecognizer.OCRObservation], vertical: Bool) -> [Int] {
        let thicknesses = indices.map {
            vertical ? observations[$0].boundingRect.width : observations[$0].boundingRect.height
        }.sorted()
        let band = thicknesses[thicknesses.count / 2] * 0.5
        let sorted = indices.sorted { lhs, rhs in
            let a = observations[lhs].boundingRect
            let b = observations[rhs].boundingRect
            let primaryA = vertical ? a.midX : a.midY
            let primaryB = vertical ? b.midX : b.midY
            if primaryA != primaryB { return primaryA > primaryB }
            return lhs < rhs
        }
        var groups: [[Int]] = []
        for index in sorted {
            let rect = observations[index].boundingRect
            if let first = groups.last?.first {
                let anchor = observations[first].boundingRect
                let distance = vertical ? abs(rect.midX - anchor.midX) : abs(rect.midY - anchor.midY)
                if distance <= band {
                    groups[groups.count - 1].append(index)
                    continue
                }
            }
            groups.append([index])
        }
        return groups.flatMap { group in
            group.sorted { lhs, rhs in
                let a = observations[lhs].boundingRect
                let b = observations[rhs].boundingRect
                if vertical, a.midY != b.midY { return a.midY > b.midY }
                if !vertical, a.midX != b.midX { return a.midX < b.midX }
                return lhs < rhs
            }
        }
    }

    private static func isVertical(_ observation: TextRecognizer.OCRObservation) -> Bool {
        switch observation.direction {
            case .topToBottom: return true
            case .leftToRight, .rightToLeft: return false
            case .unknown: return observation.boundingRect.height > observation.boundingRect.width * 1.1
        }
    }

    private static func neighbors(_ lhs: TextRecognizer.OCRObservation, _ rhs: TextRecognizer.OCRObservation) -> Bool {
        guard isVertical(lhs) == isVertical(rhs) else { return false }
        let a = lhs.boundingRect
        let b = rhs.boundingRect
        let xGap = max(0, max(a.minX, b.minX) - min(a.maxX, b.maxX))
        let yGap = max(0, max(a.minY, b.minY) - min(a.maxY, b.maxY))
        let xOverlap = max(0, min(a.maxX, b.maxX) - max(a.minX, b.minX)) / max(0.0001, min(a.width, b.width))
        let yOverlap = max(0, min(a.maxY, b.maxY) - max(a.minY, b.minY)) / max(0.0001, min(a.height, b.height))
        if isVertical(lhs) {
            let thickness = min(a.width, b.width)
            return (yOverlap > 0.5 && xGap < thickness * 0.85)
                || (xOverlap > 0.6 && yGap < thickness * 0.65)
        }
        let thickness = min(a.height, b.height)
        return (xOverlap > 0.35 && yGap < thickness * 0.9)
            || (yOverlap > 0.6 && xGap < thickness * 0.65)
    }
}
