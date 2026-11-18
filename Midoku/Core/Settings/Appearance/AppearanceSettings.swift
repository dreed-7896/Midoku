//
//  AppearanceSettings.swift
//  Midoku
//
//  Created by skitty on 8/29/26.
//

import UIKit

struct AppearanceSettings: Sendable {
    var keys: [any SettingsDefault] {
        [
            useSystemAppearance,
            appearance,
            accent,
            libraryGrid,
            libraryGridStyle,
            libraryPortraitColumns,
            libraryLandscapeColumns,
            chapterGrid,
            chapterGridStyle,
            chapterPortraitColumns,
            chapterLandscapeColumns,
            layout,
            customPortraitRows,
            customLandscapeRows
        ]
    }

    let useSystemAppearance = SettingsKey<Bool>("General.useSystemAppearance", default: false)
    let appearance = SettingsKey<Int>("General.appearance", default: 1)
    let accent = SettingsKey<String>("Appearance.accent", default: MidokuAccent.defaultHex)
    let libraryGrid = SettingsKey<Bool>("Midoku.collectionGrid", default: true)
    let libraryGridStyle = SettingsKey<ChapterGridStyle>("Appearance.libraryGridStyle", default: .standard)
    let libraryPortraitColumns = SettingsKey<Int>("Appearance.libraryPortraitColumns", default: 3)
    let libraryLandscapeColumns = SettingsKey<Int>("Appearance.libraryLandscapeColumns", default: 5)
    let chapterGrid = SettingsKey<Bool>("Midoku.chapterGrid", default: false)
    let chapterGridStyle = SettingsKey<ChapterGridStyle>("Appearance.chapterGridStyle", default: .standard)
    let chapterPortraitColumns = SettingsKey<Int>("Appearance.chapterPortraitColumns", default: 3)
    let chapterLandscapeColumns = SettingsKey<Int>("Appearance.chapterLandscapeColumns", default: 5)

    let layout = SettingsKey<Layout>("Appearance.layout", default: .standard)
    let customPortraitRows = SettingsKey<Int>("Appearance.customPortraitRows", default: UIDevice.current.userInterfaceIdiom == .pad ? 5 : 2)
    let customLandscapeRows = SettingsKey<Int>("Appearance.customLandscapeRows", default: UIDevice.current.userInterfaceIdiom == .pad ? 6 : 4)
}
