import SwiftUI

/// Artwork stays neutral while its illustration and wash follow the current app accent.
struct MCArtworkPlaceholder: View {
    @AppStorage("Appearance.accent") private var accent = MidokuAccent.defaultHex
    private var accentColor: Color { Color(uiColor: MidokuAccent.uiColor(accent)) }
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let inset = max(3, width * 0.065)
            ZStack {
                Color(uiColor: .secondarySystemBackground)
                accentColor.opacity(0.09)
                RoundedRectangle(cornerRadius: max(3, width * 0.04))
                    .stroke(accentColor.opacity(0.18), lineWidth: 1)
                    .padding(inset)
                Image(systemName: "book.pages")
                    .font(.system(size: max(14, min(width, geometry.size.height) * 0.35), weight: .light))
                    .foregroundStyle(accentColor.opacity(0.7))
            }
        }.accessibilityHidden(true)
    }
}
