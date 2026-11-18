import SwiftUI

enum ChapterGridStyle: String, SettingsValue, CaseIterable {
    case standard, compact, clean
    var title: String {
        switch self { case .standard: "Default"; case .compact: "Compact"; case .clean: "Clean" }
    }
}

enum MidokuAccent {
    static let defaultHex = "#FF6B5E"

    static func uiColor(_ storedValue: String) -> UIColor {
        let value = migratedHex(storedValue)
        let hex = value.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6, let number = UInt64(hex, radix: 16) else {
            return uiColor(defaultHex)
        }
        return UIColor(
            red: CGFloat((number >> 16) & 0xFF) / 255,
            green: CGFloat((number >> 8) & 0xFF) / 255,
            blue: CGFloat(number & 0xFF) / 255,
            alpha: 1
        )
    }

    static func hex(_ color: Color) -> String {
        let value = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard value.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return defaultHex }
        return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }

    private static func migratedHex(_ value: String) -> String {
        switch value.lowercased() {
        case "forest", "#376a50": defaultHex
        case "slate": "#456178"
        case "ochre": "#7D572B"
        case "blue": "#007AFF"
        case "purple": "#AF52DE"
        case "rose": "#FF2D55"
        default: value
        }
    }

    @MainActor static func applyToWindows() {
        let color = uiColor(AppSettings.appearance.accent.get())
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows { window.tintColor = color }
        }
    }
}

private struct MidokuAccentModifier: ViewModifier {
    @AppStorage("Appearance.accent") private var accent = MidokuAccent.defaultHex
    func body(content: Content) -> some View {
        let color = Color(uiColor: MidokuAccent.uiColor(accent))
        content.tint(color).accentColor(color)
    }
}

extension View {
    func midokuAccent() -> some View { modifier(MidokuAccentModifier()) }
}
