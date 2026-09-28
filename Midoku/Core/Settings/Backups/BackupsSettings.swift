//
//  BackupsSettings.swift
//  Midoku
//
//  Created by skitty on 8/29/26.
//

import Foundation

struct BackupsSettings: Sendable {
    var keys: [any SettingsDefault] {
        autoBackups.keys
    }

    let autoBackups = AutoBackupsSettings()
}

extension BackupsSettings {
    struct AutoBackupsSettings: Sendable {
        var keys: [any SettingsDefault] {
            [
                lastBackup,
                libraryEntries,
                chapters,
                tracking,
                history,
                categories,
                readingSessions,
                vocabulary,
                updates,
                settings,
                sourceLists,
                sensitiveSettings
            ]
        }

        let lastBackup = SettingsKey<Date>("AutomaticBackups.lastBackup", default: Date.distantPast)
        let libraryEntries = SettingsKey<Bool>("AutomaticBackups.libraryEntries", default: true)
        let chapters = SettingsKey<Bool>("AutomaticBackups.chapters", default: true)
        let tracking = SettingsKey<Bool>("AutomaticBackups.tracking", default: true)
        let history = SettingsKey<Bool>("AutomaticBackups.history", default: true)
        let categories = SettingsKey<Bool>("AutomaticBackups.categories", default: true)
        let readingSessions = SettingsKey<Bool>("AutomaticBackups.readingSessions", default: true)
        let vocabulary = SettingsKey<Bool>("AutomaticBackups.vocabulary", default: true)
        let updates = SettingsKey<Bool>("AutomaticBackups.updates", default: false)
        let settings = SettingsKey<Bool>("AutomaticBackups.settings", default: true)
        let sourceLists = SettingsKey<Bool>("AutomaticBackups.sourceLists", default: true)
        let sensitiveSettings = SettingsKey<Bool>("AutomaticBackups.sensitiveSettings", default: false)
    }
}
