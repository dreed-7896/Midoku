import Foundation

/// One app-managed iCloud Drive document. Replacing this fixed path keeps cloud usage
/// to one .aib file; iCloud may still retain its own file versions outside the app.
actor CloudBackupManager {
    static let shared = CloudBackupManager()

    enum CloudError: LocalizedError {
        case unavailable, missing, downloadTimedOut, invalid, writeFailed, emptyLibrary

        var errorDescription: String? {
            switch self {
                case .unavailable: "iCloud Drive is unavailable. Check your iCloud account and this app's iCloud entitlement."
                case .missing: "There is no Midoku backup in iCloud yet."
                case .downloadTimedOut: "The iCloud backup has not finished downloading. Try again shortly."
                case .invalid: "The iCloud backup could not be read."
                case .writeFailed: "The iCloud backup could not be saved."
                case .emptyLibrary: "An iCloud backup already exists. Import it before automatic backups replace an empty library."
            }
        }
    }

    private func backupURL() throws -> URL {
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            throw CloudError.unavailable
        }
        return container.appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
            .appendingPathComponent("Midoku-Latest.aib")
    }

    func latestBackupDate() throws -> Date? {
        let url = try backupURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    func saveLatestBackup(automatic: Bool = false) async throws {
        // Verify availability before building a potentially large backup.
        let url = try backupURL()
        let options = BackupManager.BackupOptions(
            automatic: true,
            libraryEntries: true,
            history: true,
            chapters: true,
            tracking: true,
            readingSessions: true,
            vocabulary: false,
            updates: false,
            categories: true,
            settings: false,
            sourceLists: true,
            sensitiveSettings: false
        )
        let backup = try await BackupManager.shared.createBackup(options: options)
        if automatic, FileManager.default.fileExists(atPath: url.path),
           let data = backup.collectionData,
           let collection = try? JSONDecoder().decode(MCCollectionSnapshot.self, from: data),
           collection.library.entries.isEmpty, backup.library?.isEmpty != false {
            throw CloudError.emptyLibrary
        }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(backup)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        var coordinatorError: NSError?
        var writeError: Error?
        let writeOptions: NSFileCoordinator.WritingOptions = FileManager.default.fileExists(atPath: url.path) ? .forReplacing : []
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: writeOptions, error: &coordinatorError) { target in
            do { try data.write(to: target, options: .atomic) }
            catch { writeError = error }
        }
        if let coordinatorError { throw coordinatorError }
        if let writeError { throw writeError }
        guard FileManager.default.fileExists(atPath: url.path) else { throw CloudError.writeFailed }
        AppSettings.backups.iCloudBackups.lastBackup.set(backup.date)
    }

    func importLatestBackup() async throws {
        let url = try backupURL()
        guard FileManager.default.fileExists(atPath: url.path) else { throw CloudError.missing }

        // A backup from another device may be an iCloud placeholder until requested.
        let manager = FileManager.default
        let values = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        if let status = values.ubiquitousItemDownloadingStatus, status != .current {
            try manager.startDownloadingUbiquitousItem(at: url)
            var downloaded = false
            for _ in 0..<120 {
                if try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus == .current {
                    downloaded = true
                    break
                }
                try await Task.sleep(nanoseconds: 500_000_000)
            }
            guard downloaded else { throw CloudError.downloadTimedOut }
        }

        var coordinatorError: NSError?
        var readError: Error?
        var data: Data?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinatorError) { source in
            do { data = try Data(contentsOf: source) }
            catch { readError = error }
        }
        if let coordinatorError { throw coordinatorError }
        if let readError { throw readError }
        guard let data, (try? PropertyListDecoder().decode(Backup.self, from: data)) != nil else {
            throw CloudError.invalid
        }

        // Import a local copy so the existing backup details and confirmation flow
        // can restore it, even when iCloud is subsequently unavailable.
        let temporary = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".aib")
        defer { try? manager.removeItem(at: temporary) }
        try data.write(to: temporary, options: .atomic)
        guard await BackupManager.shared.importBackup(from: temporary) else { throw CloudError.invalid }
    }
}
