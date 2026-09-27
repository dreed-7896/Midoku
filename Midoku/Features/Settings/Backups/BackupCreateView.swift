//
//  BackupCreateView.swift
//  Midoku
//
//  Created by Skitty on 9/28/25.
//

import SwiftUI

struct BackupCreateView: View {
    @State private var name = ""
    @State private var libraryEntries = true
    @State private var chapters = true
    @State private var tracking = true
    @State private var history = true
    @State private var readingSessions = true
    @State private var vocabulary = false
    @State private var updates = false
    @State private var categories = true
    @State private var settings = true
    @State private var sourceLists = true
    @State private var sensitiveSettings = false
    @State private var backupError: String?
    @State private var isSaving = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PlatformNavigationStack {
            List {
                Section {
                    TextField(NSLocalizedString("BACKUP_NAME"), text: $name)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                } header: {
                    Text(NSLocalizedString("BACKUP_NAME"))
                }
                Section {
                    Toggle(NSLocalizedString("LIBRARY_ENTRIES"), isOn: $libraryEntries)
                    Toggle(NSLocalizedString("CHAPTERS"), isOn: $chapters)
                    Toggle(NSLocalizedString("TRACKING"), isOn: $tracking)
                    Toggle(NSLocalizedString("HISTORY"), isOn: $history)
                    Toggle(NSLocalizedString("CATEGORIES"), isOn: $categories)
                    Toggle(NSLocalizedString("READING_SESSIONS"), isOn: $readingSessions)
                    Toggle(NSLocalizedString("VOCABULARY"), isOn: $vocabulary)
                    Toggle(NSLocalizedString("MANGA_UPDATES"), isOn: $updates)
                } header: {
                    Text(NSLocalizedString("LIBRARY"))
                }
                Section {
                    Toggle(NSLocalizedString("SETTINGS"), isOn: $settings)
                    Toggle(NSLocalizedString("SOURCE_LISTS"), isOn: $sourceLists)
                    Toggle(NSLocalizedString("SENSITIVE_SETTINGS"), isOn: $sensitiveSettings)
                } header: {
                    Text(NSLocalizedString("SETTINGS"))
                }
            }
            .navigationTitle(NSLocalizedString("CREATE_BACKUP"))
            .navigationBarTitleDisplayMode(.inline)
            .alert(NSLocalizedString("BACKUP_ERROR"), isPresented: Binding(
                get: { backupError != nil },
                set: { if !$0 { backupError = nil } }
            )) {
                Button(NSLocalizedString("OK"), role: .cancel) { backupError = nil }
            } message: {
                Text(backupError ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    DoneButton {
                        guard !isSaving else { return }
                        isSaving = true
                        Task {
                            do {
                                try await BackupManager.shared.saveNewBackup(
                                    name: name,
                                    options: .init(
                                        libraryEntries: libraryEntries,
                                        history: history,
                                        chapters: chapters,
                                        tracking: tracking,
                                        readingSessions: readingSessions,
                                        vocabulary: vocabulary,
                                        updates: updates,
                                        categories: categories,
                                        settings: settings,
                                        sourceLists: sourceLists,
                                        sensitiveSettings: sensitiveSettings
                                    )
                                )
                                dismiss()
                            } catch {
                                backupError = error.localizedDescription
                            }
                            isSaving = false
                        }
                    }
                }
            }
        }
    }
}
