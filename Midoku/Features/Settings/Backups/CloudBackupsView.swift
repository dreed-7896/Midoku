import SwiftUI

struct CloudBackupsView: View {
    @StateObject private var enabled = UserDefaultsBool(key: AppSettings.backups.iCloudBackups.enabled.key)
    @State private var latestDate: Date?
    @State private var isAvailable = true
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var imported = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PlatformNavigationStack {
            List {
                Section {
                    SettingView(setting: .init(
                        key: AppSettings.backups.iCloudBackups.enabled.key,
                        title: "Automatic iCloud Backup",
                        value: .toggle(.init())
                    ))
                    if enabled.value {
                        SettingView(setting: .init(
                            key: AppSettings.backups.iCloudBackups.interval.key,
                            title: "Backup Frequency",
                            value: .select(.init(
                                values: ["daily", "2days", "weekly"],
                                titles: [NSLocalizedString("DAILY"), NSLocalizedString("EVERY_2_DAYS"), NSLocalizedString("WEEKLY")]
                            ))
                        ))
                    }
                } footer: {
                    Text("Saves one .aib file containing library entries, chapters and reading progress, categories, history, tracking, and source links. Downloaded pages and app settings are excluded. iOS chooses when background backups run.")
                }

                Section {
                    HStack {
                        Text("Latest in iCloud")
                        Spacer()
                        if let latestDate {
                            Text(latestDate, format: .dateTime.date().hour().minute())
                                .foregroundStyle(.secondary)
                        } else {
                            Text(isAvailable ? "None" : "Unavailable")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button("Back Up Now") { runBackup() }
                        .disabled(isBusy || !isAvailable)
                    Button("Import Latest Backup") { importBackup() }
                        .disabled(isBusy || latestDate == nil)
                    if isBusy { ProgressView() }
                } footer: {
                    Text("Import adds a local copy to Backups. Select it there to review and restore. Each new iCloud backup replaces the previous app-managed file.")
                }
            }
            .navigationTitle("iCloud Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { CloseButton { dismiss() } }
            }
            .task { await refresh() }
            .onChange(of: enabled.value) { _ in reschedule() }
            .onReceive(NotificationCenter.default.publisher(for: .init(AppSettings.backups.iCloudBackups.interval.key))) { _ in
                reschedule()
            }
            .alert("iCloud Backup", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Backup Imported", isPresented: $imported) {
                Button("OK") { dismiss() }
            } message: {
                Text("The iCloud backup is in your local Backups list. Select it to restore.")
            }
        }
    }

    private func refresh() async {
        do {
            latestDate = try await CloudBackupManager.shared.latestBackupDate()
            isAvailable = true
        } catch {
            latestDate = nil
            isAvailable = false
            errorMessage = error.localizedDescription
        }
    }

    private func reschedule() {
        Task { await BackupManager.shared.scheduleAutoBackup() }
    }

    private func runBackup() {
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await CloudBackupManager.shared.saveLatestBackup()
                await refresh()
                reschedule()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func importBackup() {
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await CloudBackupManager.shared.importLatestBackup()
                imported = true
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
