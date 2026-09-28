//
//  BackupManager.swift
//  Midoku
//
//  Created by Skitty on 2/26/22.
//

import Foundation
import UIKit

actor BackupManager {
    static let shared = BackupManager()

    static let directory = FileManager.default.documentDirectory.appendingPathComponent("Backups", isDirectory: true)

    static var backupUrls: [URL] {
        Self.directory.contentsByDateModified
    }


    private static let excludedSettings: Set<String> = [
        AppSettings.browse.sourceLists.key, // stored separately
        "General.icloudSync",
        "iCloudBackups.enabled",
        "iCloudBackups.interval",
        "iCloudBackups.lastBackup"
    ]
    static let excludedSettingsPrefixes = [
        "Flag",
        "Data"
    ]
    static let allowedSettingsPrefixes = [
        "General",
        "Appearance",
        "Library",
        "Browse",
        "History",
        "Reader",
        "Tracker",
        "Tracking",
        "AutomaticBackups",
        "Downloads",
        "Manga",
        "Logs",
        "Search",
        "Token",
        "Dictionary"
    ]

    func save(backup: Backup, url: URL? = nil) throws {
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let plist = try encoder.encode(backup)
        if let url {
            try plist.write(to: url, options: .atomic)
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let path = backup.automatic == true
                ? Self.directory.appendingPathComponent("Midoku-Automatic.aib")
                : Self.directory.appendingPathComponent("midoku_\(dateFormatter.string(from: backup.date)).aib")
            try plist.write(to: path, options: .atomic)
        }
        NotificationCenter.default.post(name: .updateBackupList, object: nil)
    }

    func saveNewBackup(name: String = "", options: BackupOptions) async throws {
        let backup = try await createBackup(name: name, options: options)
        try save(backup: backup)
    }

    func importBackup(from url: URL) -> Bool {
        Self.directory.createDirectory()
        var targetLocation = Self.directory.appendingPathComponent(url.lastPathComponent)
        while targetLocation.exists {
            targetLocation = targetLocation.deletingLastPathComponent().appendingPathComponent(
                targetLocation.deletingPathExtension().lastPathComponent.appending("_1")
            ).appendingPathExtension(url.pathExtension)
        }
        let secured = url.startAccessingSecurityScopedResource()
        defer {
            if secured {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            try FileManager.default.copyItem(at: url, to: targetLocation)
            NotificationCenter.default.post(name: .updateBackupList, object: nil)
            return true
        } catch {
            return false
        }
    }

    struct BackupOptions {
        var automatic: Bool = false
        let libraryEntries: Bool
        let history: Bool
        let chapters: Bool
        let tracking: Bool
        let readingSessions: Bool
        let vocabulary: Bool
        let updates: Bool
        let categories: Bool
        let settings: Bool
        let sourceLists: Bool
        let sensitiveSettings: Bool
    }

    func createBackup(name: String = "", options: BackupOptions) async throws -> Backup {
        let sourceLists: [String] = if options.sourceLists {
            await SourceManager.shared.getSourceListURLs().map { $0.absoluteString }
        } else {
            []
        }
        let collectionData: Data?
        let collectionEntryCount: Int?
        if options.libraryEntries {
            let collection = try await MainActor.run { () throws -> (Data, Int) in
                let store = MCCollectionStore.shared
                return (try store.backupData(), store.library.entries.count)
            }
            collectionData = collection.0
            collectionEntryCount = collection.1
        } else {
            collectionData = nil
            collectionEntryCount = nil
        }
        return await CoreDataManager.shared.container.performBackgroundTask { context in
            let library: [BackupLibraryManga] = if options.libraryEntries {
                CoreDataManager.shared.getLibraryManga(context: context).map {
                    BackupLibraryManga(libraryObject: $0, skipCategories: !options.categories)
                }
            } else {
                []
            }
            let history: [BackupHistory] = if options.history {
                CoreDataManager.shared.getHistory(context: context).map {
                    BackupHistory(historyObject: $0)
                }
            } else {
                []
            }
            let manga: [BackupManga] = if options.libraryEntries {
                CoreDataManager.shared.getManga(context: context).map {
                    BackupManga(mangaObject: $0)
                }
            } else {
                []
            }
            let chapters: [BackupChapter] = if options.chapters {
                CoreDataManager.shared.getChapters(context: context).map {
                    BackupChapter(chapterObject: $0)
                }
            } else {
                []
            }
            let trackItems: [BackupTrackItem] = if options.tracking {
                CoreDataManager.shared.getTracks(context: context).compactMap {
                    BackupTrackItem(trackObject: $0)
                }
            } else {
                []
            }
            let sessionItems: [BackupReadingSession] = if options.readingSessions {
                CoreDataManager.shared.getSessions(context: context).compactMap(BackupReadingSession.init)
            } else {
                []
            }
            let vocabulary: [BackupVocabEntry] = if options.vocabulary {
                CoreDataManager.shared.getVocab(context: context).compactMap(BackupVocabEntry.init)
            } else {
                []
            }
            let updateItems: [BackupUpdate] = if options.updates {
                CoreDataManager.shared.getUpdates(context: context).compactMap(BackupUpdate.init)
            } else {
                []
            }
            let categories: [BackupCategory] = if options.categories {
                CoreDataManager.shared.getCategories(context: context).compactMap(BackupCategory.init)
            } else {
                []
            }
            let sources: [BackupSource] = CoreDataManager.shared.getSources(context: context).compactMap(BackupSource.init)

            let settings: [String: JSONAnyValue]? = if options.settings {
                self.exportSettings(includeSensitive: options.sensitiveSettings, sourceKeys: sources.map(\.id))
            } else {
                nil
            }

            return Backup(
                collectionData: collectionData,
                collectionEntryCount: collectionEntryCount,
                library: library,
                history: history,
                manga: manga,
                chapters: chapters,
                trackItems: trackItems,
                readingSessions: sessionItems,
                vocabulary: vocabulary,
                updates: updateItems,
                categories: categories,
                sources: sources,
                sourceLists: sourceLists,
                settings: settings,
                date: Date.now,
                name: name.isEmpty ? nil : name,
                automatic: options.automatic,
                version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
            )
        }
    }

    private nonisolated func exportSettings(includeSensitive: Bool, sourceKeys: [String]) -> [String: JSONAnyValue] {
        var allSettings = UserDefaults.standard.dictionaryRepresentation()

        // filter out potentially sensitive info
        if !includeSensitive {
            let sensitiveKeywords = ["login", "password", "token", "auth", "cookie"]
            for key in allSettings.keys where sensitiveKeywords.contains(where: key.lowercased().contains) {
                allSettings.removeValue(forKey: key)
            }
        }

        var convertedSettings: [String: JSONAnyValue] = [:]

        // convert to export compatible types
        for (key, value) in allSettings {
            guard
                Self.allowedSettingsPrefixes.contains(where: { key.hasPrefix($0) }) || sourceKeys.contains(where: { key.hasPrefix($0) }),
                !Self.excludedSettings.contains(key)
            else {
                continue
            }
            if
                let number = value as? NSNumber,
                CFGetTypeID(number) == CFBooleanGetTypeID()
            {
                convertedSettings[key] = .bool(number.boolValue)
            } else if let value = value as? String {
                convertedSettings[key] = .string(value)
            } else if let value = value as? Int {
                convertedSettings[key] = .int(value)
            } else if let value = value as? Double {
                convertedSettings[key] = .double(value)
            } else if let value = value as? Bool {
                convertedSettings[key] = .bool(value)
            } else if let value = value as? [String] {
                convertedSettings[key] = .array(value)
            }
        }

        return convertedSettings
    }

    func renameBackup(url: URL, name: String?) -> Bool {
        guard var backup = Backup.load(from: url) else { return false }
        backup.name = name?.isEmpty ?? true ? nil : name
        do {
            try save(backup: backup, url: url)
            return true
        } catch { return false }
    }

    func removeBackup(url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: Restoring
extension BackupManager {
    enum BackupError: Error {
        case manga
        case categories
        case library
        case history
        case chapters
        case sessions
        case vocabulary
        case updates
        case track
        case sources

        var stringValue: String {
            switch self {
                case .manga: NSLocalizedString("CONTENT")
                case .categories: NSLocalizedString("CATEGORIES")
                case .library: NSLocalizedString("LIBRARY")
                case .history: NSLocalizedString("HISTORY")
                case .chapters: NSLocalizedString("CHAPTERS")
                case .sessions: NSLocalizedString("READING_SESSIONS")
                case .vocabulary: NSLocalizedString("VOCABULARY")
                case .updates: NSLocalizedString("UPDATES")
                case .track: NSLocalizedString("TRACKERS")
                case .sources: NSLocalizedString("SOURCES")
            }
        }
    }

    func restore(from url: URL) async -> Bool {
        guard let backup = Backup.load(from: url) else { return false }
        if let data = backup.collectionData {
            do {
                let candidate = try JSONDecoder().decode(MCCollectionSnapshot.self, from: data)
                try candidate.validate()
                try await MainActor.run { try MCCollectionStore.shared.restore(data) }
            } catch { return false }
        }
        return await doRestore(from: backup)
    }

    @discardableResult
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func doRestore(from backup: Backup) async -> Bool {
        await MainActor.run {
            UIApplication.shared.appDelegate?.showLoadingIndicator()
            UIApplication.shared.isIdleTimerDisabled = true
        }

        let sourceListsTask = Task {
            await SourceManager.shared.waitForSourceListsLoad()
            // restore source lists
            guard let sourceLists = backup.sourceLists else { return }
            await SourceManager.shared.clearSourceLists()
            for sourceList in sourceLists {
                guard let sourceListURL = URL(string: sourceList) else { continue }
                _ = await SourceManager.shared.addSourceList(url: sourceListURL, allowUnavailable: true)
            }
        }

        let mangaTask = Task {
            if let backupManga = backup.manga {
                let result = await CoreDataManager.shared.container.performBackgroundTask { context in
                    CoreDataManager.shared.clearManga(context: context)
                    for item in backupManga {
                        _ = item.toObject(context: context)
                    }
                    do {
                        try context.save()
                        return true
                    } catch {
                        return false
                    }
                }
                if !result {
                    throw BackupError.manga
                }
            }
        }
        let categoriesTask = Task {
            if let backupCategories = backup.categories {
                let result = await CoreDataManager.shared.container.performBackgroundTask { context in
                    CoreDataManager.shared.clearCategories(context: context)
                    for category in backupCategories {
                        _ = category.toObject(context: context)
                    }
                    do {
                        try context.save()
                        return true
                    } catch {
                        return false
                    }
                }
                if !result {
                    throw BackupError.categories
                }
            }
        }
        let libraryTask = Task {
            try await mangaTask.value
            try await categoriesTask.value
            if let backupLibrary = backup.library {
                let result = await CoreDataManager.shared.container.performBackgroundTask { context in
                    CoreDataManager.shared.clearLibrary(context: context)
                    let mangaByKey = Dictionary(
                        CoreDataManager.shared.getManga(context: context).map {
                            ($0.identifier, $0)
                        },
                        uniquingKeysWith: { first, _ in first }
                    )
                    let categoryByTitle = Dictionary(
                        CoreDataManager.shared.getCategories(context: context).compactMap { category in
                            category.title.map { ($0, category) }
                        },
                        uniquingKeysWith: { first, _ in first }
                    )
                    for libraryBackupItem in backupLibrary {
                        let libraryObject = libraryBackupItem.toObject(context: context)
                        if let manga = mangaByKey[libraryBackupItem.identifier] {
                            libraryObject.manga = manga
                            if let categories = libraryBackupItem.categories, !categories.isEmpty {
                                libraryObject.categories = NSSet(array: categories.compactMap { categoryByTitle[$0] })
                            }
                        }
                    }
                    do {
                        try context.save()
                        return true
                    } catch {
                        return false
                    }
                }
                if !result {
                    throw BackupError.library
                }
            }
        }
        let historyTask = Task {
            if let backupHistory = backup.history {
                let result = await CoreDataManager.shared.container.performBackgroundTask { context in
                    CoreDataManager.shared.clearHistory(context: context)
                    for item in backupHistory {
                        _ = item.toObject(context: context)
                    }
                    do {
                        try context.save()
                        return true
                    } catch {
                        return false
                    }
                }
                if !result {
                    throw BackupError.history
                }
            }
        }
        let chaptersTask = Task {
            try await historyTask.value // need to link chapters with history
            try await libraryTask.value // need to make sure manga objects aren't being modified
            if let backupChapters = backup.chapters {
                let result = await CoreDataManager.shared.container.performBackgroundTask { context in
                    CoreDataManager.shared.clearChapters(context: context)
                    let mangaByKey = Dictionary(
                        CoreDataManager.shared.getManga(context: context).map {
                            ($0.identifier, $0)
                        },
                        uniquingKeysWith: { first, _ in first }
                    )
                    let historyByKey = Dictionary(
                        CoreDataManager.shared.getHistory(context: context).map {
                            ($0.identifier, $0)
                        },
                        uniquingKeysWith: { first, _ in first }
                    )
                    for backupChapter in backupChapters {
                        let chapter = backupChapter.toObject(context: context)
                        chapter.manga = mangaByKey[chapter.identifier.mangaIdentifier]
                        chapter.history = historyByKey[chapter.identifier]
                    }
                    do {
                        try context.save()
                        return true
                    } catch {
                        return false
                    }
                }
                if !result {
                    throw BackupError.chapters
                }
            }
        }
        let updatesTask = Task {
            try await chaptersTask.value // need to link updates with chapters
            if let backupUpdates = backup.updates {
                let result = await CoreDataManager.shared.container.performBackgroundTask { context in
                    CoreDataManager.shared.clearUpdates(context: context)
                    let chaptersByKey = Dictionary(
                        CoreDataManager.shared.getChapters(context: context).map {
                            ($0.identifier, $0)
                        },
                        uniquingKeysWith: { first, _ in first }
                    )
                    for backupUpdate in backupUpdates {
                        let update = backupUpdate.toObject(context: context)
                        update.chapter = chaptersByKey[update.identifier]
                    }
                    do {
                        try context.save()
                        return true
                    } catch {
                        return false
                    }
                }
                if !result {
                    throw BackupError.updates
                }
            }
        }
        let sessionsTask = Task {
            try await chaptersTask.value // need to link sessions with history, after being updated by chapters
            if let backupSessions = backup.readingSessions {
                let result = await CoreDataManager.shared.container.performBackgroundTask { context in
                    CoreDataManager.shared.clearSessions(context: context)
                    let historyByKey = Dictionary(
                        CoreDataManager.shared.getHistory(context: context).map {
                            ($0.identifier, $0)
                        },
                        uniquingKeysWith: { first, _ in first }
                    )
                    for backupSession in backupSessions {
                        // ensure data is valid
                        guard backupSession.endDate > backupSession.startDate && backupSession.pagesRead > 0 else {
                            continue
                        }
                        let session = backupSession.toObject(context: context)
                        session.history = historyByKey[backupSession.identifier]
                    }
                    do {
                        try context.save()
                        return true
                    } catch {
                        return false
                    }
                }
                if !result {
                    throw BackupError.sessions
                }
            }
        }
        let vocabTask = Task {
            if let vocabItems = backup.vocabulary {
                let result = await CoreDataManager.shared.container.performBackgroundTask { context in
                    CoreDataManager.shared.clearVocab(context: context)
                    for item in vocabItems {
                        _ = item.toObject(context: context)
                    }
                    do {
                        try context.save()
                        return true
                    } catch {
                        return false
                    }
                }
                if !result {
                    throw BackupError.vocabulary
                }
            }
        }
        let trackTask = Task {
            if let backupTrackItems = backup.trackItems {
                let result = await CoreDataManager.shared.container.performBackgroundTask { context in
                    CoreDataManager.shared.clearTracks(context: context)
                    for item in backupTrackItems {
                        _ = item.toObject(context: context)
                    }
                    do {
                        try context.save()
                        return true
                    } catch {
                        return false
                    }
                }
                if !result {
                    throw BackupError.track
                }
            }
        }
        let sourceTask = Task {
            await sourceListsTask.value
            if let sourceItems = backup.sources {
                let (result, needsRefresh) = await CoreDataManager.shared.container.performBackgroundTask { context in
                    var needsRefresh = false
                    for item in sourceItems {
                        guard item.config != nil else { continue }
                        CoreDataManager.shared.removeSource(key: item.id, context: context)
                        _ = item.toObject(context: context)
                        needsRefresh = true
                    }
                    do {
                        try context.save()
                        return (true, needsRefresh)
                    } catch {
                        return (false, false)
                    }
                }
                if !result {
                    throw BackupError.sources
                }
                if needsRefresh {
                    await SourceManager.shared.reloadSources()
                }
            }
        }

        var backupError: Error?

        // wait for db changes to finish
        do {
            try await updatesTask.value
            try await sessionsTask.value
            try await vocabTask.value
            try await trackTask.value
            try await sourceTask.value
        } catch {
            backupError = error
        }

        // Restore application and currently installed source settings as part of the initial restore.
        await restoreSettings(from: backup)

        await Task { @MainActor in
            await UIApplication.shared.appDelegate?.hideLoadingIndicator()
            UIApplication.shared.isIdleTimerDisabled = false
        }.value

        if backupError == nil {
            let externalSourceKeys = Set((backup.sources ?? []).lazy.filter { $0.config == nil }.map(\.id))
            let missingSourceKeys = await SourceManager.shared.missingExternalSourceKeys(in: externalSourceKeys)

            if
                !missingSourceKeys.isEmpty,
                Reachability.getConnectionType() != .none,
                await confirmExternalSourceRestore(keys: missingSourceKeys)
            {
                await MainActor.run {
                    UIApplication.shared.isIdleTimerDisabled = true
                    UIApplication.shared.appDelegate?.showLoadingIndicator(
                        style: .progress,
                        message: NSLocalizedString("INSTALLING_SOURCES")
                    )
                }

                var installedSourceKeys: Set<String> = []

                if let (installedSourceKeyStream, total) = await SourceManager.shared.installExternalSources(keys: missingSourceKeys) {
                    var current = 0
                    for await key in installedSourceKeyStream {
                        current += 1
                        installedSourceKeys.insert(key)
                        await UIApplication.shared.appDelegate?.updateLoadingIndicator(
                            progress: Float(current - 1) / Float(total)
                        )
                    }
                }

                await restoreSettings(from: backup, sourceKeys: installedSourceKeys)

                await Task { @MainActor in
                    let appDelegate = UIApplication.shared.appDelegate
                    appDelegate?.updateLoadingIndicator(progress: 1)
                    await appDelegate?.hideLoadingIndicator()
                    UIApplication.shared.isIdleTimerDisabled = false
                }.value
            }
        }

        NotificationCenter.default.post(name: .updateHistory, object: nil)
        NotificationCenter.default.post(name: .updateTrackers, object: nil)
        NotificationCenter.default.post(name: .updateCategories, object: nil)
        NotificationCenter.default.post(name: .updateLibrary, object: nil)

        let backupSourceKeys = backup.sources?.map { $0.id } ?? []
        let missingSourceKeys = await SourceManager.shared.missingExternalSourceKeys(in: Set(backupSourceKeys))

        await Task { @MainActor [backupError] in
            let delegate = UIApplication.shared.appDelegate
            if let backupError {
                // show error alert
                delegate?.presentAlert(
                    title: NSLocalizedString("BACKUP_ERROR"),
                    message: String(
                        format: NSLocalizedString("BACKUP_ERROR_TEXT"),
                        (backupError as? BackupError)?.stringValue ?? NSLocalizedString("UNKNOWN")
                    )
                )
            } else {
                // show missing sources alert if there are any
                if !missingSourceKeys.isEmpty {
                    delegate?.presentAlert(
                        title: NSLocalizedString("MISSING_SOURCES"),
                        message: NSLocalizedString("MISSING_SOURCES_TEXT") + missingSourceKeys.map { "\n\($0)" }.joined()
                    )
                }
            }
        }.value

        return backupError == nil
    }

    private func restoreSettings(from backup: Backup, sourceKeys: Set<String>? = nil) async {
        guard let settings = backup.settings else { return }

        let sourceKeyPrefixes: [String]
        if let sourceKeys {
            sourceKeyPrefixes = sourceKeys.map { "\($0)." }
        } else {
            // only restore source settings for sources installed, or built-in sources that will be added from the backup restore
            let sources = await SourceManager.shared.getSourceInfos(sorted: false)
            sourceKeyPrefixes = sources.map { "\($0.sourceId)." } + (backup.sources ?? []).compactMap {
                $0.config == nil ? nil : "\($0.id)."
            }
        }

        var needsMigrate = false

        for (key, value) in settings {
            let hasAllowedPrefix = (sourceKeys == nil && Self.allowedSettingsPrefixes.contains { key.hasPrefix($0) })
                || sourceKeyPrefixes.contains { key.hasPrefix($0) }
            guard
                hasAllowedPrefix,
                !Self.excludedSettings.contains(key),
                !Self.excludedSettingsPrefixes.contains(where: { key.hasPrefix($0) })
            else {
                continue
            }
            UserDefaults.standard.set(value.toRaw(), forKey: key)
            if AppDelegate.legacySettingKeys.contains(key) {
                needsMigrate = true
            }
        }

        if needsMigrate {
            await MainActor.run {
                UIApplication.shared.appDelegate?.migrateSettings()
            }
        }
    }

    private func confirmExternalSourceRestore(keys: Set<String>) async -> Bool {
        let message = NSLocalizedString("RESTORE_MISSING_SOURCES_TEXT") + keys.sorted().map { "\n\($0)" }.joined()

        return await withCheckedContinuation { continuation in
            Task { @MainActor in
                guard
                    let delegate = UIApplication.shared.appDelegate,
                    delegate.topViewController != nil
                else {
                    continuation.resume(returning: false)
                    return
                }
                delegate.presentAlert(
                    title: NSLocalizedString("RESTORE_MISSING_SOURCES"),
                    message: message,
                    actions: [
                        UIAlertAction(title: NSLocalizedString("CANCEL"), style: .cancel) { _ in
                            continuation.resume(returning: false)
                        },
                        UIAlertAction(title: NSLocalizedString("INSTALL_SOURCES"), style: .default) { _ in
                            continuation.resume(returning: true)
                        }
                    ]
                )
            }
        }
    }
}

// MARK: Automatic Backups
extension BackupManager {
    /// A single atomic file is replaced only after a new backup is successfully built.
    func createAutoBackupIfNeeded() async {
        let url = Self.directory.appendingPathComponent("Midoku-Automatic.aib")
        if let existing = BackupInfo.load(from: url),
           Date.now.timeIntervalSince(existing.date) < 5 * 60 * 60 {
            return
        }
        do {
            try await saveNewBackup(options: .init(
                automatic: true,
                libraryEntries: AppSettings.backups.autoBackups.libraryEntries.get(),
                history: AppSettings.backups.autoBackups.history.get(),
                chapters: AppSettings.backups.autoBackups.chapters.get(),
                tracking: AppSettings.backups.autoBackups.tracking.get(),
                readingSessions: AppSettings.backups.autoBackups.readingSessions.get(),
                vocabulary: AppSettings.backups.autoBackups.vocabulary.get(),
                updates: AppSettings.backups.autoBackups.updates.get(),
                categories: AppSettings.backups.autoBackups.categories.get(),
                settings: AppSettings.backups.autoBackups.settings.get(),
                sourceLists: AppSettings.backups.autoBackups.sourceLists.get(),
                sensitiveSettings: AppSettings.backups.autoBackups.sensitiveSettings.get()
            ))
            AppSettings.backups.autoBackups.lastBackup.set(Date.now)
        } catch {
            LogManager.logger.error("Could not save automatic backup: \(error)")
        }
    }
}
