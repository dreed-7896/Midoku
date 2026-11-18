import SwiftUI
import UIKit

/// Midoku Web's placeholder cover (`.cover`): two flat colours, one shape, a short rule and the title
/// in a serif face, like a printed book cover. The palette is picked from the title so it stays stable.
enum MDCoverArt {
    enum Motif { case sun, moon, dot, ring }
    struct Art { let c1: UInt32; let c2: UInt32; let ink: UInt32; let motif: Motif }

    static let palette: [Art] = [
        Art(c1: 0x1E2A44, c2: 0xE9B872, ink: 0xF4EBDD, motif: .sun),
        Art(c1: 0x4A1F2E, c2: 0xF27A6B, ink: 0xFBE3DC, motif: .moon),
        Art(c1: 0x17423A, c2: 0xF2C14E, ink: 0xEAF4EE, motif: .dot),
        Art(c1: 0x2A2148, c2: 0x7FA7FF, ink: 0xE6E8FF, motif: .ring),
        Art(c1: 0x12343F, c2: 0x8FD3C7, ink: 0xE2F5F1, motif: .sun),
        Art(c1: 0x3A2340, c2: 0xE58FD0, ink: 0xF8E5F3, motif: .dot),
        Art(c1: 0x5A3415, c2: 0xFF9F5A, ink: 0xFFE9D6, motif: .moon),
        Art(c1: 0x183447, c2: 0x9CC8E8, ink: 0xE6F1FA, motif: .moon),
        Art(c1: 0x1D1A3A, c2: 0xB48CFF, ink: 0xECE4FF, motif: .sun),
        Art(c1: 0x3D2A1E, c2: 0xD9733F, ink: 0xF5E2D3, motif: .ring),
        Art(c1: 0x163A2A, c2: 0x7FE0A8, ink: 0xE3F7EC, motif: .dot),
        Art(c1: 0x2E2A1A, c2: 0xE8D47A, ink: 0xF7F1D6, motif: .ring)
    ]

    static func art(for seed: String?) -> Art {
        guard let seed, !seed.isEmpty else { return palette[0] }
        var hash: UInt32 = 5381
        for byte in seed.utf8 { hash = (hash &* 33) &+ UInt32(byte) }
        return palette[Int(hash % UInt32(palette.count))]
    }

    static func uiColor(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    static func color(_ hex: UInt32) -> Color { Color(uiColor: uiColor(hex)) }

    /// Frame of the shape in a cover of the given size (CSS `.cover__shape--*`).
    static func shapeRect(_ motif: Motif, in size: CGSize) -> CGRect {
        let w = size.width, h = size.height
        switch motif {
        case .sun: return CGRect(x: w - w * 0.72 + w * 0.14, y: h * 0.10, width: w * 0.72, height: w * 0.72)
        case .moon: return CGRect(x: -w * 0.12, y: h * 0.52, width: w * 1.25, height: w * 1.25)
        case .dot: return CGRect(x: w * 0.14, y: h * 0.22, width: w * 0.36, height: w * 0.36)
        case .ring: return CGRect(x: w * 0.10, y: h * 0.16, width: w * 0.80, height: w * 0.80)
        }
    }

    static func titleFont(size: CGFloat) -> UIFont {
        UIFont(name: "Fraunces-SemiBold", size: size)
            ?? UIFont(descriptor: UIFontDescriptor(name: "Georgia-Bold", size: size), size: size)
    }

    @MainActor private static let cache = NSCache<NSString, UIImage>()

    /// The placeholder as an image, for UIKit image views.
    @MainActor
    static func image(title: String?, size: CGSize = CGSize(width: 200, height: 300)) -> UIImage {
        let key = "\(title ?? "")|\(Int(size.width))x\(Int(size.height))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let art = art(for: title)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let rect = CGRect(origin: .zero, size: size)
            uiColor(art.c1).setFill()
            context.fill(rect)
            context.cgContext.saveGState()
            context.cgContext.clip(to: rect)
            let shape = shapeRect(art.motif, in: size)
            if art.motif == .ring {
                let line = size.width * 0.07
                let path = UIBezierPath(ovalIn: shape.insetBy(dx: line / 2, dy: line / 2))
                path.lineWidth = line
                uiColor(art.c2).setStroke()
                path.stroke()
            } else {
                uiColor(art.c2).setFill()
                UIBezierPath(ovalIn: shape).fill()
            }
            context.cgContext.restoreGState()
            let pad = size.width * 0.09
            uiColor(art.ink).withAlphaComponent(0.7).setFill()
            context.fill(CGRect(x: pad, y: pad, width: size.width * 0.2, height: 2))
            if let title, !title.isEmpty {
                let font = titleFont(size: size.width * 0.115)
                let style = NSMutableParagraphStyle()
                style.lineHeightMultiple = 0.95
                style.lineBreakMode = .byTruncatingTail
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: uiColor(art.ink), .paragraphStyle: style]
                let width = size.width - pad * 2
                let bounds = (title as NSString).boundingRect(with: CGSize(width: width, height: size.height * 0.5),
                                                              options: [.usesLineFragmentOrigin], attributes: attributes, context: nil)
                let height = min(ceil(bounds.height), size.height * 0.5)
                (title as NSString).draw(with: CGRect(x: pad, y: size.height - pad - height, width: width, height: height),
                                         options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes, context: nil)
            }
        }
        cache.setObject(image, forKey: key)
        return image
    }
}

/// SwiftUI version of `MDCoverArt`.
struct MCArtworkPlaceholder: View {
    var title: String?

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let art = MDCoverArt.art(for: title)
            let pad = size.width * 0.09
            let shape = MDCoverArt.shapeRect(art.motif, in: size)
            ZStack(alignment: .topLeading) {
                MDCoverArt.color(art.c1)
                Group {
                    if art.motif == .ring {
                        Circle().strokeBorder(MDCoverArt.color(art.c2), lineWidth: size.width * 0.07)
                    } else {
                        Circle().fill(MDCoverArt.color(art.c2))
                    }
                }
                .frame(width: shape.width, height: shape.height)
                .offset(x: shape.minX, y: shape.minY)
                Rectangle().fill(MDCoverArt.color(art.ink).opacity(0.7))
                    .frame(width: size.width * 0.2, height: 2)
                    .offset(x: pad, y: pad)
                if let title, !title.isEmpty, size.width >= 60 {
                    Text(title)
                        .font(Font(MDCoverArt.titleFont(size: max(8, size.width * 0.115))))
                        .lineSpacing(-size.width * 0.01)
                        .foregroundStyle(MDCoverArt.color(art.ink))
                        .lineLimit(4)
                        .frame(width: max(0, size.width - pad * 2), height: max(0, size.height - pad * 2), alignment: .bottomLeading)
                        .offset(x: pad, y: pad)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
            .overlay(Rectangle().strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
        }
        .accessibilityHidden(true)
    }
}

/// Midoku Web's placeholder chapter thumbnail (`.page-thumb`): a manga page drawn as panels.
struct MCPagePlaceholder: View {
    var layout = 0

    private static let light = Color(red: 0xF4 / 255, green: 0xF2 / 255, blue: 0xEC / 255)
    private static let mid = Color(red: 0xCF / 255, green: 0xCA / 255, blue: 0xC0 / 255)
    private static let tone = Color(red: 0xB9 / 255, green: 0xB4 / 255, blue: 0xAA / 255)
    private static let dark = Color(red: 0x3A / 255, green: 0x38 / 255, blue: 0x35 / 255)

    private static let layouts: [[(CGFloat, CGFloat, CGFloat, CGFloat, Color)]] = [
        [(6, 5, 88, 36, mid), (6, 44, 43, 51, light), (51, 44, 43, 51, dark)],
        [(6, 5, 88, 27, light), (6, 35, 55, 30, tone), (64, 35, 30, 30, light), (6, 68, 88, 27, dark)],
        [(6, 5, 50, 90, mid), (59, 5, 35, 43, light), (59, 51, 35, 44, dark)],
        [(6, 5, 43, 30, light), (51, 5, 43, 30, mid), (6, 38, 88, 30, dark), (6, 71, 43, 24, light), (51, 71, 43, 24, tone)]
    ]

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width / 100, h = geometry.size.height / 100
            let panels = Self.layouts[abs(layout) % Self.layouts.count]
            ZStack(alignment: .topLeading) {
                Color(red: 0xEC / 255, green: 0xE9 / 255, blue: 0xE2 / 255)
                ForEach(panels.indices, id: \.self) { index in
                    let panel = panels[index]
                    Rectangle().fill(panel.4)
                        .overlay(Rectangle().strokeBorder(Color(white: 0.11), lineWidth: 1.5))
                        .frame(width: panel.2 * w, height: panel.3 * h)
                        .offset(x: panel.0 * w, y: panel.1 * h)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .clipped()
        }
        .accessibilityHidden(true)
    }
}
