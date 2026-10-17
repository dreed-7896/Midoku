import Foundation

nonisolated protocol MCSettingChoice: RawRepresentable, CaseIterable, Identifiable, Codable, Hashable, Sendable where RawValue == String {
    var title: String { get }
}
extension MCSettingChoice {
    nonisolated var id: String { rawValue }
}

nonisolated enum MCAppAppearance: String, MCSettingChoice {
    case system, light, dark
    var title: String { rawValue.capitalized }
}
nonisolated enum MCAppAccent: String, MCSettingChoice {
    case forest, slate, ochre
    var title: String { rawValue.capitalized }
}
nonisolated enum MCCoverDensity: String, MCSettingChoice {
    case comfortable, compact
    var title: String { rawValue.capitalized }
    var minimumWidth: Double { self == .compact ? 100 : 140 }
}
nonisolated enum MCLaunchTab: String, MCSettingChoice {
    case home, library, browse, history, settings
    var title: String { rawValue.capitalized }
}
nonisolated enum MCLibrarySort: String, MCSettingChoice {
    case title, recentlyRead, recentlyAdded, recentlyUpdated
    var title: String {
        switch self {
        case .title: "Title"
        case .recentlyRead: "Recently read"
        case .recentlyAdded: "Recently added"
        case .recentlyUpdated: "Recently updated"
        }
    }
}
nonisolated enum MCReaderMode: String, MCSettingChoice {
    case rightToLeft, leftToRight, continuous
    var title: String {
        switch self {
        case .rightToLeft: "Right to left"
        case .leftToRight: "Left to right"
        case .continuous: "Continuous"
        }
    }
}
nonisolated enum MCTapZones: String, MCSettingChoice {
    case edges, wideForward
    var title: String { self == .edges ? "Balanced edges" : "Larger next-page zone" }
    func action(at fraction: Double, mode: MCReaderMode) -> Int {
        guard mode != .continuous else { return 0 }
        let position = mode == .rightToLeft ? 1 - fraction : fraction
        if position < 0.25 { return -1 }
        if position > (self == .edges ? 0.75 : 0.5) { return 1 }
        return 0
    }
}
nonisolated enum MCReaderFit: String, MCSettingChoice {
    case width, screen
    var title: String { self == .width ? "Fit width" : "Fit screen" }
}
nonisolated enum MCReaderBackground: String, MCSettingChoice {
    case black, paper, system
    var title: String { rawValue.capitalized }
}
nonisolated enum MCReaderOrientation: String, MCSettingChoice {
    case automatic, portrait, landscape
    var title: String { rawValue.capitalized }
}
nonisolated enum MCLockDelay: String, MCSettingChoice {
    case immediately, oneMinute, fiveMinutes
    var seconds: TimeInterval {
        switch self { case .immediately: 0; case .oneMinute: 60; case .fiveMinutes: 300 }
    }
    var title: String {
        switch self { case .immediately: "Immediately"; case .oneMinute: "After 1 minute"; case .fiveMinutes: "After 5 minutes" }
    }
}
nonisolated struct MCReaderPreferences: Codable, Equatable, Sendable {
    var mode: MCReaderMode = .rightToLeft
    var tapNavigation = true
    var tapZones: MCTapZones = .edges
    var fit: MCReaderFit = .width
    var background: MCReaderBackground = .black
    var orientation: MCReaderOrientation = .automatic
    var customBrightness = false
    var brightness = 0.6
    var keepAwake = true
}
nonisolated struct MCSourceListingIdentity: Codable, Hashable, Sendable {
    let connectionID: UUID
    let externalID: String
}

nonisolated struct MCSourceChapterIdentity: Codable, Hashable, Sendable {
    let listing: MCSourceListingIdentity
    let externalID: String
}

nonisolated struct MCMangaDetails: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let description: String
    var coverURL: URL?
    var authors: [String]? = nil
    var artists: [String]? = nil
    var status: String? = nil
    var year: String? = nil
    var tags: [String]? = nil
    var availableLanguages: [MCSourceFilterOption]? = nil
    var defaultChapterLanguage: String? = nil
    var webURL: URL? = nil
}

nonisolated struct MCChapterRecord: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    /// Exact source text; never use floating point for chapter identity or ordering.
    let number: String?
    let ordinal: Int
    let language: String?
    var groups: [String]? = nil
    var volume: String? = nil
    var uploadedAt: String? = nil
}


nonisolated struct MCSourceFilterOption: Codable, Sendable, Identifiable { let id: String; let title: String }

nonisolated struct MCReadingPosition: Codable, Sendable { let id: MCSourceChapterIdentity; var updatedAt: Date }
