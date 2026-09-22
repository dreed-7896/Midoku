//
//  GeneralSettings.swift
//  Midoku
//
//  Created by skitty on 8/29/26.
//

import UIKit

struct GeneralSettings: Sendable {
    enum OpeningTab: String, SettingsValue, CaseIterable {
        case library
        case browse
        case history
        case search
        case settings

        var title: String {
            switch self {
            case .library: "Library"
            case .browse: "Browse"
            case .history: "History"
            case .search: "Search"
            case .settings: "Settings"
            }
        }
    }

    enum AppLockDelay: String, SettingsValue, CaseIterable {
        case immediately
        case fifteenSeconds
        case thirtySeconds
        case oneMinute
        case fiveMinutes
        case fifteenMinutes

        var seconds: TimeInterval {
            switch self {
            case .immediately: 0
            case .fifteenSeconds: 15
            case .thirtySeconds: 30
            case .oneMinute: 60
            case .fiveMinutes: 300
            case .fifteenMinutes: 900
            }
        }

        var title: String {
            switch self {
            case .immediately: "Immediately"
            case .fifteenSeconds: "After 15 seconds"
            case .thirtySeconds: "After 30 seconds"
            case .oneMinute: "After 1 minute"
            case .fiveMinutes: "After 5 minutes"
            case .fifteenMinutes: "After 15 minutes"
            }
        }
    }

    var keys: [any SettingsDefault] {
        [
            incognitoMode,
            openingTab,
            appLock,
            appLockDelay,
            blurAppSwitcher,
            icloudSync
        ]
    }

    let incognitoMode = SettingsKey<Bool>("General.incognitoMode", default: false)
    let openingTab = SettingsKey<OpeningTab>("General.openingTab", default: .library)
    let appLock = SettingsKey<Bool>("General.appLock", default: false)
    let appLockDelay = SettingsKey<AppLockDelay>("General.appLockDelay", default: .oneMinute)
    let blurAppSwitcher = SettingsKey<Bool>("General.blurAppSwitcher", default: true)
    let icloudSync = SettingsKey<Bool>("General.icloudSync", default: false)
}
