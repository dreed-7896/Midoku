//
//  MidokuTheme.swift
//  Midoku
//
//  The Midoku Web look on native: boxy (square corners), dark, coral accent,
//  Inter for text, Bricolage Grotesque for headings, JetBrains Mono for labels.
//

import CoreText
import ObjectiveC
import SwiftUI
import UIKit

// MARK: - Palette

enum MDColor {
    private static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    static let bg = rgb(0x09090B)
    static let s1 = rgb(0x111114)
    static let s2 = rgb(0x18181D)
    static let s3 = rgb(0x1F1F26)
    static let line = rgb(0x23232A)
    static let line2 = rgb(0x2E2E37)
    static let text = rgb(0xF4F4F6)
    static let text2 = rgb(0xB4B4BE)
    static let text3 = rgb(0x8E8E9A)
    static let accent = rgb(0xFF6B5E)
    static let accentSoft = rgb(0xFF6B5E, 0.14)
    static let onAccent = rgb(0x0B0B0F)
    static let amber = rgb(0xFFB547)
    static let mint = rgb(0x3DD6A3)
    static let tabBar = rgb(0x09090B, 0.9)
}

extension Color {
    static let mdBg = Color(uiColor: MDColor.bg)
    static let mdS1 = Color(uiColor: MDColor.s1)
    static let mdS2 = Color(uiColor: MDColor.s2)
    static let mdS3 = Color(uiColor: MDColor.s3)
    static let mdLine = Color(uiColor: MDColor.line)
    static let mdLine2 = Color(uiColor: MDColor.line2)
    static let mdText = Color(uiColor: MDColor.text)
    static let mdText2 = Color(uiColor: MDColor.text2)
    static let mdText3 = Color(uiColor: MDColor.text3)
    static let mdAccent = Color(uiColor: MDColor.accent)
    static let mdAccentSoft = Color(uiColor: MDColor.accentSoft)
}

// MARK: - Fonts

enum MDFont {
    static let files = [
        "Inter-Regular", "Inter-Medium", "Inter-SemiBold", "Inter-Bold",
        "BricolageGrotesque-SemiBold", "BricolageGrotesque-Bold", "BricolageGrotesque-ExtraBold",
        "JetBrainsMono-Medium", "JetBrainsMono-SemiBold", "JetBrainsMono-Bold"
    ]

    nonisolated(unsafe) private(set) static var available = false

    static func register() {
        for name in files {
            let url = Bundle.main.url(forResource: name, withExtension: "ttf")
                ?? Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
            guard let url else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        available = UIFont(name: "Inter-Regular", size: 12) != nil
    }

    static func interName(_ weight: CGFloat) -> String {
        switch weight {
        case ..<0.1: "Inter-Regular"
        case ..<0.27: "Inter-Medium"
        case ..<0.35: "Inter-SemiBold"
        default: "Inter-Bold"
        }
    }

    static func displayName(_ weight: CGFloat) -> String {
        switch weight {
        case ..<0.35: "BricolageGrotesque-SemiBold"
        case ..<0.5: "BricolageGrotesque-Bold"
        default: "BricolageGrotesque-ExtraBold"
        }
    }

    static func monoName(_ weight: CGFloat) -> String {
        switch weight {
        case ..<0.27: "JetBrainsMono-Medium"
        case ..<0.35: "JetBrainsMono-SemiBold"
        default: "JetBrainsMono-Bold"
        }
    }

    static func ui(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont? {
        UIFont(name: interName(weight.rawValue), size: size)
    }

    static func display(_ size: CGFloat, _ weight: UIFont.Weight = .bold) -> UIFont? {
        UIFont(name: displayName(weight.rawValue), size: size)
    }

    static func mono(_ size: CGFloat, _ weight: UIFont.Weight = .semibold) -> UIFont? {
        UIFont(name: monoName(weight.rawValue), size: size)
    }

    /// Web sizes (CSS px = pt) for each text style: body text is 15, headings use the display face.
    static func size(for style: UIFont.TextStyle) -> (CGFloat, UIFont.Weight, Bool) {
        switch style {
        case .largeTitle: (34, .heavy, true)
        case .title1: (28, .bold, true)
        case .title2: (22, .bold, true)
        case .title3: (20, .bold, true)
        case .headline: (16, .bold, false)
        case .subheadline: (14, .regular, false)
        case .callout: (15, .regular, false)
        case .footnote: (13, .regular, false)
        case .caption1: (12, .regular, false)
        case .caption2: (11, .regular, false)
        default: (15, .regular, false)
        }
    }

    static func preferred(_ style: UIFont.TextStyle, traits: UITraitCollection? = nil) -> UIFont? {
        let (size, weight, display) = size(for: style)
        guard let base = display ? Self.display(size, weight) : ui(size, weight) else { return nil }
        return UIFontMetrics(forTextStyle: style).scaledFont(for: base, compatibleWith: traits)
    }
}

extension Font {
    private static func inter(_ size: CGFloat, _ weight: Font.Weight, _ style: Font.TextStyle) -> Font {
        guard MDFont.available else { return .system(size: size, weight: weight) }
        return .custom(MDFont.interName(weight.mdRaw), size: size, relativeTo: style)
    }

    private static func display(_ size: CGFloat, _ weight: Font.Weight, _ style: Font.TextStyle) -> Font {
        guard MDFont.available else { return .system(size: size, weight: weight) }
        return .custom(MDFont.displayName(weight.mdRaw), size: size, relativeTo: style)
    }

    static var mdLargeTitle: Font { display(34, .heavy, .largeTitle) }
    static var mdTitle: Font { display(28, .bold, .title) }
    static var mdTitle2: Font { display(22, .bold, .title2) }
    static var mdTitle3: Font { display(20, .bold, .title3) }
    static var mdHeadline: Font { inter(16, .bold, .headline) }
    static var mdSubheadline: Font { inter(14, .regular, .subheadline) }
    static var mdBody: Font { inter(15, .regular, .body) }
    static var mdCallout: Font { inter(15, .regular, .callout) }
    static var mdFootnote: Font { inter(13, .regular, .footnote) }
    static var mdCaption: Font { inter(12, .regular, .caption) }
    static var mdCaption2: Font { inter(11, .regular, .caption2) }

    /// Mono uppercase labels (web `.kicker` / `.label`).
    static func mdMono(_ size: CGFloat = 11, weight: Font.Weight = .semibold) -> Font {
        guard MDFont.available else { return .system(size: size, weight: weight, design: .monospaced) }
        return .custom(MDFont.monoName(weight.mdRaw), size: size, relativeTo: .caption)
    }

    /// Drop-in for `.system(size:weight:design:)`.
    static func mdSystem(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design? = nil) -> Font {
        guard MDFont.available else { return .system(size: size, weight: weight, design: design ?? .default) }
        if design == .monospaced { return mdMono(size, weight: weight) }
        if size >= 20 && weight.mdRaw >= Font.Weight.bold.mdRaw { return display(size, weight, .title3) }
        return inter(size, weight, .body)
    }

    /// Drop-in for `.system(_ style:design:weight:)`.
    static func mdSystem(_ style: Font.TextStyle, design: Font.Design? = nil, weight: Font.Weight? = nil) -> Font {
        guard MDFont.available else { return .system(style, design: design, weight: weight) }
        let base: Font = switch style {
        case .largeTitle: .mdLargeTitle
        case .title: .mdTitle
        case .title2: .mdTitle2
        case .title3: .mdTitle3
        case .headline: .mdHeadline
        case .subheadline: .mdSubheadline
        case .callout: .mdCallout
        case .footnote: .mdFootnote
        case .caption: .mdCaption
        case .caption2: .mdCaption2
        default: .mdBody
        }
        if design == .monospaced {
            let (size, _, _) = MDFont.size(for: style.mdUIKit)
            return mdMono(size, weight: weight ?? .medium)
        }
        if let weight { return base.weight(weight) }
        return base
    }
}

private extension Font.Weight {
    var mdRaw: CGFloat {
        switch self {
        case .ultraLight: -0.8
        case .thin: -0.6
        case .light: -0.4
        case .regular: 0
        case .medium: 0.23
        case .semibold: 0.3
        case .bold: 0.4
        case .heavy: 0.56
        case .black: 0.62
        default: 0
        }
    }
}

private extension Font.TextStyle {
    var mdUIKit: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}

// MARK: - SwiftUI helpers

private struct MidokuStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.mdBody)
            .midokuAccent()
    }
}

extension View {
    /// Web text defaults for a SwiftUI screen: Inter body text and the accent.
    func midokuStyle() -> some View { modifier(MidokuStyleModifier()) }

    /// Web section label: mono, uppercase, letter-spaced, muted.
    func mdLabel() -> some View {
        font(.mdMono(11)).textCase(.uppercase).tracking(1).foregroundStyle(Color.mdText3)
    }
}

// MARK: - Global UIKit styling

@MainActor
enum MidokuTheme {
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        MDFont.register()
        overrideSystemColors()
        if MDFont.available { overrideSystemFonts() }
        squareBackgroundConfigurations()
        removeLiquidGlass()
        applyAppearance()
    }

    /// Dark variants of the system background, separator and label colors become the web palette.
    nonisolated private static func overrideSystemColors() {
        let map: [(String, UIColor)] = [
            ("systemBackgroundColor", MDColor.bg),
            ("secondarySystemBackgroundColor", MDColor.s1),
            ("tertiarySystemBackgroundColor", MDColor.s2),
            ("systemGroupedBackgroundColor", MDColor.bg),
            ("secondarySystemGroupedBackgroundColor", MDColor.s1),
            ("tertiarySystemGroupedBackgroundColor", MDColor.s2),
            ("separatorColor", MDColor.line),
            ("opaqueSeparatorColor", MDColor.line2),
            ("labelColor", MDColor.text),
            ("secondaryLabelColor", MDColor.text2),
            ("tertiaryLabelColor", MDColor.text3)
        ]
        typealias Getter = @convention(c) (AnyClass, Selector) -> UIColor
        for (name, dark) in map {
            let selector = NSSelectorFromString(name)
            guard let method = class_getClassMethod(UIColor.self, selector) else { continue }
            let original = unsafeBitCast(method_getImplementation(method), to: Getter.self)
            let light = original(UIColor.self, selector)
            let color = UIColor { traits in
                traits.userInterfaceStyle == .dark ? dark : light.resolvedColor(with: traits)
            }
            let block: @convention(block) (AnyObject) -> UIColor = { _ in color }
            method_setImplementation(method, imp_implementationWithBlock(block))
        }
    }

    /// Runs `make` unless a font override is already running on this thread (UIKit can call the
    /// overridden methods while building a font), in which case the system font is used.
    nonisolated private static func guarded(_ make: () -> UIFont?, fallback: () -> UIFont) -> UIFont {
        let key = "MidokuTheme.fontOverride"
        let dictionary = Thread.current.threadDictionary
        if dictionary[key] != nil { return fallback() }
        dictionary[key] = true
        defer { dictionary.removeObject(forKey: key) }
        return make() ?? fallback()
    }

    /// UIKit text (labels, cells, alerts, bars) uses Inter instead of San Francisco.
    nonisolated private static func overrideSystemFonts() {
        let cls: AnyClass = UIFont.self

        typealias SizeWeight = @convention(c) (AnyClass, Selector, CGFloat, CGFloat) -> UIFont
        let sizeWeightSelector = NSSelectorFromString("systemFontOfSize:weight:")
        if let method = class_getClassMethod(cls, sizeWeightSelector) {
            let original = unsafeBitCast(method_getImplementation(method), to: SizeWeight.self)
            let block: @convention(block) (AnyClass, CGFloat, CGFloat) -> UIFont = { c, size, weight in
                guarded({ MDFont.ui(size, UIFont.Weight(rawValue: weight)) }) {
                    original(c, sizeWeightSelector, size, weight)
                }
            }
            method_setImplementation(method, imp_implementationWithBlock(block))
        }

        typealias Size = @convention(c) (AnyClass, Selector, CGFloat) -> UIFont
        for (name, weight) in [("systemFontOfSize:", UIFont.Weight.regular), ("boldSystemFontOfSize:", .bold)] {
            let selector = NSSelectorFromString(name)
            guard let method = class_getClassMethod(cls, selector) else { continue }
            let original = unsafeBitCast(method_getImplementation(method), to: Size.self)
            let block: @convention(block) (AnyClass, CGFloat) -> UIFont = { c, size in
                guarded({ MDFont.ui(size, weight) }) { original(c, selector, size) }
            }
            method_setImplementation(method, imp_implementationWithBlock(block))
        }

        typealias Style = @convention(c) (AnyClass, Selector, NSString) -> UIFont
        let styleSelector = NSSelectorFromString("preferredFontForTextStyle:")
        if let method = class_getClassMethod(cls, styleSelector) {
            let original = unsafeBitCast(method_getImplementation(method), to: Style.self)
            let block: @convention(block) (AnyClass, NSString) -> UIFont = { c, style in
                guarded({ MDFont.preferred(UIFont.TextStyle(rawValue: style as String)) }) {
                    original(c, styleSelector, style)
                }
            }
            method_setImplementation(method, imp_implementationWithBlock(block))
        }

        typealias StyleTraits = @convention(c) (AnyClass, Selector, NSString, UITraitCollection?) -> UIFont
        let styleTraitsSelector = NSSelectorFromString("preferredFontForTextStyle:compatibleWithTraitCollection:")
        if let method = class_getClassMethod(cls, styleTraitsSelector) {
            let original = unsafeBitCast(method_getImplementation(method), to: StyleTraits.self)
            let block: @convention(block) (AnyClass, NSString, UITraitCollection?) -> UIFont = { c, style, traits in
                guarded({ MDFont.preferred(UIFont.TextStyle(rawValue: style as String), traits: traits) }) {
                    original(c, styleTraitsSelector, style, traits)
                }
            }
            method_setImplementation(method, imp_implementationWithBlock(block))
        }
    }

    /// Square corners for list cells and button backgrounds (UIKit and SwiftUI lists).
    nonisolated private static func squareBackgroundConfigurations() {
        guard let cls = NSClassFromString("UIBackgroundConfiguration") else { return }
        let selector = NSSelectorFromString("cornerRadius")
        guard let method = class_getInstanceMethod(cls, selector) else { return }
        let block: @convention(block) (AnyObject) -> CGFloat = { _ in 0 }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    /// Midoku Web is flat and boxy: bar buttons lose their glass capsules, scroll views lose the
    /// blurred edge under the bars, and sheets get square corners.
    nonisolated private static func removeLiquidGlass() {
        func method(_ className: String, _ name: String) -> Method? {
            guard let cls = NSClassFromString(className) else { return nil }
            return class_getInstanceMethod(cls, NSSelectorFromString(name))
        }
        let yes: @convention(block) (AnyObject) -> Bool = { _ in true }
        for (className, name) in [("UIBarButtonItem", "hidesSharedBackground"), ("UIScrollEdgeEffect", "isHidden")] {
            if let m = method(className, name) { method_setImplementation(m, imp_implementationWithBlock(yes)) }
        }
        let zero: @convention(block) (AnyObject) -> CGFloat = { _ in 0 }
        if let m = method("UISheetPresentationController", "preferredCornerRadius") {
            method_setImplementation(m, imp_implementationWithBlock(zero))
        }
    }

    private static func applyAppearance() {
        let titleFont = MDFont.display(17, .bold) ?? .systemFont(ofSize: 17, weight: .semibold)
        let largeFont = MDFont.display(34, .heavy) ?? .systemFont(ofSize: 34, weight: .bold)

        let bar = UINavigationBarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor = MDColor.bg
        bar.shadowColor = MDColor.line
        bar.titleTextAttributes = [.font: titleFont, .foregroundColor: MDColor.text]
        bar.largeTitleTextAttributes = [.font: largeFont, .foregroundColor: MDColor.text, .kern: -1.0]
        if let buttonFont = MDFont.ui(15, .semibold) {
            let button = UIBarButtonItemAppearance()
            button.normal.titleTextAttributes = [.font: buttonFont]
            bar.buttonAppearance = button
            bar.doneButtonAppearance = button
            bar.backButtonAppearance = button
        }
        let edge = bar.copy()
        edge.shadowColor = .clear
        let navigationBar = UINavigationBar.appearance()
        navigationBar.standardAppearance = bar
        navigationBar.compactAppearance = bar
        navigationBar.scrollEdgeAppearance = edge
        navigationBar.compactScrollEdgeAppearance = edge

        let toolbar = UIToolbarAppearance()
        toolbar.configureWithOpaqueBackground()
        toolbar.backgroundColor = MDColor.s2
        toolbar.shadowColor = MDColor.line2
        UIToolbar.appearance().standardAppearance = toolbar
        UIToolbar.appearance().scrollEdgeAppearance = toolbar

        UISwitch.appearance().onTintColor = MDColor.accent
        UIRefreshControl.appearance().tintColor = MDColor.text3
        UITableView.appearance().separatorColor = MDColor.line

        if let segmentFont = MDFont.ui(13, .medium), let segmentSelected = MDFont.ui(13, .semibold) {
            let segment = UISegmentedControl.appearance()
            segment.selectedSegmentTintColor = MDColor.text
            segment.backgroundColor = MDColor.s1
            segment.setTitleTextAttributes([.font: segmentFont, .foregroundColor: MDColor.text2], for: .normal)
            segment.setTitleTextAttributes([.font: segmentSelected, .foregroundColor: MDColor.onAccent], for: .selected)
        }
    }
}
