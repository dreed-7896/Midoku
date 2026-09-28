//
//  AutomaticBackupsView.swift
//  Midoku
//
//  Created by Skitty on 11/13/25.
//

import SwiftUI

struct AutomaticBackupsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PlatformNavigationStack {
            List {
                Section {
                    Text("When the app opens, its one automatic backup is replaced if it is at least 5 hours old.")
                } footer: {
                    let date = AppSettings.backups.autoBackups.lastBackup.get()
                    if date > Date.distantPast {
                        Text(String(format: NSLocalizedString("LAST_BACKED_UP_%@"), date.formatted(.relative(presentation: .named))))
                    }
                }

                Section(NSLocalizedString("LIBRARY")) {
                        toggle(key: AppSettings.backups.autoBackups.libraryEntries.key, title: NSLocalizedString("LIBRARY_ENTRIES"))
                        toggle(key: AppSettings.backups.autoBackups.chapters.key, title: NSLocalizedString("CHAPTERS"))
                        toggle(key: AppSettings.backups.autoBackups.tracking.key, title: NSLocalizedString("TRACKING"))
                        toggle(key: AppSettings.backups.autoBackups.history.key, title: NSLocalizedString("HISTORY"))
                        toggle(key: AppSettings.backups.autoBackups.categories.key, title: NSLocalizedString("CATEGORIES"))
                        toggle(key: AppSettings.backups.autoBackups.readingSessions.key, title: NSLocalizedString("READING_SESSIONS"))
                        toggle(key: AppSettings.backups.autoBackups.vocabulary.key, title: NSLocalizedString("VOCABULARY"))
                        toggle(key: AppSettings.backups.autoBackups.updates.key, title: NSLocalizedString("MANGA_UPDATES"))
                    }
                Section(NSLocalizedString("SETTINGS")) {
                        toggle(key: AppSettings.backups.autoBackups.settings.key, title: NSLocalizedString("SETTINGS"))
                        toggle(key: AppSettings.backups.autoBackups.sourceLists.key, title: NSLocalizedString("SOURCE_LISTS"))
                        toggle(key: AppSettings.backups.autoBackups.sensitiveSettings.key, title: NSLocalizedString("SENSITIVE_SETTINGS"))
                    }
            }
            .navigationTitle(NSLocalizedString("AUTOMATIC_BACKUPS"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton {
                        dismiss()
                    }
                }
            }
        }
    }

    func toggle(key: String, title: String) -> some View {
        SettingView(
            setting: .init(
                key: key,
                title: title,
                value: .toggle(.init())
            )
        )
    }
}
