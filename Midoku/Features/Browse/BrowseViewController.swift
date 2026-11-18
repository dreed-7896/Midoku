//
//  BrowseViewController.swift
//  Midoku (iOS)
//
//  Created by Skitty on 1/23/22.
//
//  Midoku Web's Sources page for the extensions on this device: Installed / Available tabs, an
//  updates banner, search with a language box, pinned extensions as big tiles and the rest as a
//  three-column grid of tiles.
//

import AidokuRunner
import SafariServices
import SwiftUI

@MainActor
@Observable
final class ExtensionsModel {
    @ObservationIgnored let viewModel = BrowseViewModel()

    var pinned: [SourceInfo] = []
    var installed: [SourceInfo] = []
    var updates: [SourceInfo] = []
    var available: [ExternalSourceInfo] = []
    var loaded = false
    var busy: Set<String> = []
    var updatingAll = false

    var allInstalled: [SourceInfo] { pinned + installed }

    func reloadInstalled() async {
        await viewModel.loadInstalledSources()
        await viewModel.loadPinnedSources()
        viewModel.loadUpdates()
        publish()
    }

    func reloadExternal(reload: Bool = false) async {
        await viewModel.loadExternalSources(reload: reload)
        viewModel.loadUpdates()
        publish()
    }

    private func publish() {
        pinned = viewModel.pinnedSources
        installed = viewModel.installedSources
        updates = viewModel.updatesSources
        available = availableSources()
        loaded = true
        AppSettings.browse.updateCount.set(updates.count)
    }

    func hasUpdate(_ info: SourceInfo) -> Bool {
        updates.contains { $0.sourceId == info.sourceId }
    }

    private func availableSources() -> [ExternalSourceInfo] {
        let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).map(SemanticVersion.init)
        let installedIDs = Set(allInstalled.map(\.sourceId))
        let ratings = AppSettings.browse.contentRatings.get()
        return viewModel.unfilteredExternalSources
            .filter { info in
                guard !installedIDs.contains(info.id) else { return false }
                if let appVersion, let min = info.minAppVersion, SemanticVersion(min) > appVersion { return false }
                if let appVersion, let max = info.maxAppVersion, SemanticVersion(max) < appVersion { return false }
                return ratings.contains(info.resolvedContentRating)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func install(_ info: ExternalSourceInfo) async -> Bool {
        guard let url = info.fileURL else { return false }
        busy.insert(info.id)
        defer { busy.remove(info.id) }
        return await SourceManager.shared.importSource(from: url) != nil
    }

    func update(_ sourceId: String) async {
        guard let external = viewModel.unfilteredExternalSources.first(where: { $0.id == sourceId }),
              let url = external.fileURL else { return }
        busy.insert(sourceId)
        _ = await SourceManager.shared.importSource(from: url)
        busy.remove(sourceId)
    }

    func updateAll() async {
        updatingAll = true
        for info in updates { await update(info.sourceId) }
        updatingAll = false
        await reloadInstalled()
    }
}

class BrowseViewController: UIViewController, MDBarlessScreen {
    private let model = ExtensionsModel()
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Sources"
        view.backgroundColor = MDColor.bg
        navigationItem.largeTitleDisplayMode = .never

        let page = ExtensionsPageView(
            model: model,
            onBack: (navigationController?.viewControllers.first === self) ? nil : { [weak self] in self?.navigationController?.popViewController(animated: true) },
            onAdd: { [weak self] in self?.openAddSourcePage() },
            onMigrate: { [weak self] in self?.openMigrateSourcePage() },
            onOpen: { [weak self] in self?.open($0) },
            onLatest: { [weak self] in self?.openLatest($0) },
            onUninstall: { [weak self] in self?.uninstall(sourceKeys: [$0.sourceId]) },
            onGuide: { [weak self] in self?.openGuidePage() }
        ).midokuStyle()
        let host = UIHostingController(rootView: page)
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)

        observers.append(NotificationCenter.default.addObserver(forName: .updateSourceList, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                await self?.model.reloadInstalled()
                self?.checkUpdateCount()
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .updateSourceLists, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                await self?.model.reloadExternal()
                self?.checkUpdateCount()
            }
        })

        Task {
            await model.reloadInstalled()
            await model.reloadExternal()
            checkUpdateCount()
            if model.viewModel.hasLegacySourceList && !AppSettings.flags.showedLegacySourceListNotice.get() {
                showLegacySourceListNotice()
                AppSettings.flags.showedLegacySourceListNotice.set(true)
            }
        }
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isToolbarHidden = true
    }

    private func open(_ info: SourceInfo) {
        guard !info.disabled, let source = SourceManager.shared.store.source(for: info.sourceId) else { return }
        let controller: UIViewController = if let legacy = source.legacySource {
            SourceViewController(source: legacy)
        } else {
            NewSourceViewController(source: source)
        }
        navigationController?.pushViewController(controller, animated: true)
    }

    private func openLatest(_ info: SourceInfo) {
        guard let source = SourceManager.shared.store.source(for: info.sourceId) else { return }
        Task {
            let names: [String]
            if let legacy = source.legacySource {
                names = legacy.listings.map(\.name)
            } else {
                names = (try? await source.getListings())?.map(\.name) ?? []
            }
            guard let index = names.firstIndex(where: {
                $0.range(of: #"\b(latest|new|recent)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
            }) else {
                presentAlert(title: "Latest unavailable", message: "This extension does not provide a Latest or New tab.")
                return
            }
            let controller: UIViewController = if let legacy = source.legacySource {
                SourceViewController(source: legacy, initialListingIndex: index)
            } else {
                NewSourceViewController(source: source, initialListingIndex: index)
            }
            navigationController?.pushViewController(controller, animated: true)
        }
    }

    func uninstall(sourceKeys: [String]) {
        let containsLocalSource = sourceKeys.contains(where: { $0 == LocalSourceRunner.sourceKey })

        func commit() {
            Task {
                for key in sourceKeys {
                    await SourceManager.shared.remove(sourceKey: key, skipUpdateNotification: true)
                }
                await self.model.reloadInstalled()
                self.checkUpdateCount()
            }
        }

        if containsLocalSource {
            presentAlert(
                title: NSLocalizedString("REMOVE_LOCAL_SOURCE"),
                message: NSLocalizedString("REMOVE_LOCAL_SOURCE_TEXT"),
                actions: [
                    UIAlertAction(title: NSLocalizedString("CANCEL"), style: .cancel),
                    UIAlertAction(title: NSLocalizedString("OK"), style: .default) { _ in
                        Task { await LocalFileManager.shared.removeAllLocalFiles() }
                        commit()
                    }
                ]
            )
        } else {
            commit()
        }
    }

    // store update count and display badge
    func checkUpdateCount() {
        let updateCount = model.updates.count
        AppSettings.browse.updateCount.set(updateCount)
        (tabBarController as? TabBarController)?.setSourcesBadge(updateCount)
    }

    func showLegacySourceListNotice() {
        let alert = UIAlertController(
            title: NSLocalizedString("LEGACY_SOURCE_LIST_WARNING"),
            message: NSLocalizedString("LEGACY_SOURCE_LIST_WARNING_INFO"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK"), style: .cancel) { _ in })
        present(alert, animated: true)
    }

    func openGuidePage() {
        let safariViewController = SFSafariViewController(
            url: URL(string: "https://aidoku.app/help/guides/getting-started/#installing-a-source")!
        )
        present(safariViewController, animated: true)
    }

    func openMigrateSourcePage() {
        let viewController = SwiftUINavigationViewController(rootView: MigrateSourcesView(), hidesNavigationBar: true)
        viewController.modalPresentationStyle = .pageSheet
        present(viewController, animated: true)
    }

    func openAddSourcePage() {
        let path = NavigationCoordinator(rootViewController: self)
        let hostingController = UIHostingController(
            rootView: AddSourceView(externalSources: model.viewModel.unfilteredExternalSources)
                .ignoresSafeArea() // fixes some weird keyboard clipping stuff
                .environmentObject(path)
        )
        path.rootViewController = hostingController
        hostingController.modalPresentationStyle = .pageSheet
        present(hostingController, animated: true)
    }
}

// MARK: - Page

private enum ExtensionsTab { case installed, available }

private func languageLabel(_ languages: [String]) -> String {
    let codes = languages.filter { $0 != "multi" }
    if codes.count > 1 || languages.contains("multi") { return "Multi" }
    return (codes.first ?? "").uppercased()
}

struct ExtensionsPageView: View {
    @Bindable var model: ExtensionsModel
    var onBack: (() -> Void)?
    var onAdd: () -> Void
    var onMigrate: () -> Void
    var onOpen: (SourceInfo) -> Void
    var onLatest: (SourceInfo) -> Void
    var onUninstall: (SourceInfo) -> Void
    var onGuide: () -> Void

    @State private var tab: ExtensionsTab = .installed
    @State private var query = ""
    @State private var language = ""
    @State private var failedInstall: String?

    private func matches(name: String, languages: [String]) -> Bool {
        (query.isEmpty || name.localizedCaseInsensitiveContains(query))
            && (language.isEmpty || languages.contains(language) || (language == "multi" && languages.count > 1))
    }

    private var languages: [String] {
        let all = model.allInstalled.flatMap(\.languages) + model.available.flatMap { $0.languages ?? [$0.lang ?? ""] }
        return Array(Set(all.filter { !$0.isEmpty })).sorted {
            SourceLanguage.displayName(for: $0).localizedCaseInsensitiveCompare(SourceLanguage.displayName(for: $1)) == .orderedAscending
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let onBack {
                    MDIconButton(systemImage: "chevron.left", label: "Back", action: onBack)
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                }

                MDPageHeader(kicker: "\(model.allInstalled.count) installed · On this device", title: "Sources") {
                    MDIconButton(systemImage: "arrow.left.arrow.right", label: NSLocalizedString("MIGRATE_SOURCES"), action: onMigrate)
                    MDIconButton(systemImage: "plus", label: NSLocalizedString("ADD_SOURCE"), action: onAdd)
                }

                segmented.padding(.horizontal, 16).padding(.top, 16)

                if tab == .installed && !model.updates.isEmpty {
                    updatesBanner.padding(.horizontal, 16).padding(.top, 12)
                }

                HStack(spacing: 8) {
                    MDSearchField(text: $query, prompt: "Search extensions", autofocus: false)
                    languageBox
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                if tab == .installed { installedContent } else { availableContent }
            }
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await model.reloadExternal(reload: true) }
        .background(Color.mdBg.ignoresSafeArea())
        .alert("Couldn't install", isPresented: Binding(get: { failedInstall != nil }, set: { if !$0 { failedInstall = nil } })) {
            Button(NSLocalizedString("OK"), role: .cancel) {}
        } message: {
            Text("\(failedInstall ?? "The extension") could not be installed.")
        }
    }

    // `.segmented--lg`
    private var segmented: some View {
        HStack(spacing: 0) {
            segment("Installed · \(model.allInstalled.count)", on: tab == .installed) { tab = .installed }
            Rectangle().fill(Color.mdLine2).frame(width: 1)
            segment("Available · \(model.available.count)", on: tab == .available) { tab = .available }
        }
        .frame(height: 44)
        .overlay(Rectangle().strokeBorder(Color.mdLine2, lineWidth: 1))
    }

    private func segment(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.mdSystem(size: 14, weight: on ? .semibold : .medium))
                .foregroundStyle(on ? Color(uiColor: MDColor.onAccent) : Color.mdText2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(on ? Color.mdText : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // `.banner`
    private var updatesBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.clockwise").font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.mdAccent)
            Text("\(model.updates.count) update\(model.updates.count == 1 ? "" : "s") available")
                .font(.mdSystem(size: 14, weight: .semibold))
                .foregroundStyle(Color.mdText)
            Spacer(minLength: 0)
            Button {
                Task { await model.updateAll() }
            } label: {
                Group {
                    if model.updatingAll { ProgressView().tint(Color(uiColor: MDColor.onAccent)) } else { Text("Update all") }
                }
                .font(.mdSystem(size: 13, weight: .semibold))
                .foregroundStyle(Color(uiColor: MDColor.onAccent))
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(Color.mdAccent)
            }
            .buttonStyle(.plain)
            .disabled(model.updatingAll)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.mdAccentSoft)
    }

    // `.select-box`
    private var languageBox: some View {
        Menu {
            Button { language = "" } label: {
                if language.isEmpty { Label("All languages", systemImage: "checkmark") } else { Text("All languages") }
            }
            ForEach(languages, id: \.self) { code in
                Button { language = code } label: {
                    let name = SourceLanguage.displayName(for: code)
                    if language == code { Label(name, systemImage: "checkmark") } else { Text(name) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(language.isEmpty ? "All languages" : SourceLanguage.displayName(for: language))
                    .font(.mdSystem(size: 13, weight: .semibold))
                    .foregroundStyle(Color.mdText)
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.mdText2)
            }
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background(Color.mdS1)
            .overlay(Rectangle().strokeBorder(Color.mdLine, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Language")
    }

    @ViewBuilder private var installedContent: some View {
        let pinned = model.pinned.filter { matches(name: $0.name, languages: $0.languages) }
        let rest = model.installed.filter { matches(name: $0.name, languages: $0.languages) }
        if !pinned.isEmpty {
            section("Pinned") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                    ForEach(pinned, id: \.sourceId) { info in
                        Button { onOpen(info) } label: { bigTile(info) }
                            .buttonStyle(.plain)
                            .mdLongPressActions(info.name) { menu(info, pinned: true) }
                    }
                }
            }
        }
        if !rest.isEmpty {
            section("Installed") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 18) {
                    ForEach(rest, id: \.sourceId) { info in
                        Button { onOpen(info) } label: { tile(info) }
                            .buttonStyle(.plain)
                            .mdLongPressActions(info.name) { menu(info, pinned: false) }
                    }
                }
            }
        }
        if model.loaded && pinned.isEmpty && rest.isEmpty {
            if model.allInstalled.isEmpty {
                emptyState(title: NSLocalizedString("BROWSE_NO_SOURCES"), detail: NSLocalizedString("BROWSE_NO_SOURCES_TEXT_NEW"),
                           action: NSLocalizedString("ADDING_SOURCES_GUIDE_BUTTON"), perform: onGuide)
            } else {
                emptyState(title: "No extensions match", detail: "Try another name.")
            }
        }
    }

    @ViewBuilder private var availableContent: some View {
        let items = model.available.filter { matches(name: $0.name, languages: $0.languages ?? [$0.lang ?? ""]) }
        if !items.isEmpty {
            section("Available") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 18) {
                    ForEach(items, id: \.id) { info in availableTile(info) }
                }
            }
        } else if model.loaded {
            if model.available.isEmpty && !model.viewModel.unfilteredExternalSources.isEmpty {
                emptyState(title: NSLocalizedString("ALL_SOURCES_INSTALLED"), detail: NSLocalizedString("ALL_SOURCES_INSTALLED_INFO"))
            } else if model.viewModel.unfilteredExternalSources.isEmpty {
                emptyState(title: NSLocalizedString("NO_EXTERNAL_SOURCES"), detail: NSLocalizedString("NO_EXTERNAL_SOURCES_INFO"),
                           action: NSLocalizedString("ADD_SOURCE"), perform: onAdd)
            } else {
                emptyState(title: "No extensions match", detail: "Try another name.")
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).mdLabel()
            content()
        }
        .padding(.horizontal, 16)
        .padding(.top, 26)
    }

    private func menu(_ info: SourceInfo, pinned: Bool) -> [MDActionRow] {
        var rows: [MDActionRow] = [
            MDActionRow(systemImage: "magnifyingglass", title: "Browse", detail: info.name) { onOpen(info) },
            MDActionRow(systemImage: "clock", title: "Latest") { onLatest(info) }
        ]
        if model.hasUpdate(info) {
            rows.append(MDActionRow(systemImage: "arrow.clockwise", title: NSLocalizedString("UPDATE")) { Task { await model.update(info.sourceId) } })
        }
        rows.append(MDActionRow(systemImage: pinned ? "pin.slash" : "pin", title: pinned ? NSLocalizedString("UNPIN") : NSLocalizedString("PIN")) {
            if pinned {
                SourceManager.shared.unpin(sourceKey: info.sourceId)
            } else {
                SourceManager.shared.pin(sourceKey: info.sourceId)
            }
        })
        rows.append(MDActionRow(systemImage: info.disabled ? "play" : "pause", title: info.disabled ? NSLocalizedString("ENABLE") : NSLocalizedString("DISABLE")) {
            Task {
                if info.disabled {
                    await SourceManager.shared.enable(sourceKey: info.sourceId)
                } else {
                    await SourceManager.shared.disable(sourceKey: info.sourceId)
                }
            }
        })
        rows.append(MDActionRow(systemImage: "trash", title: NSLocalizedString("UNINSTALL"), destructive: true) { onUninstall(info) })
        return rows
    }

    // `.tile.tile--big`
    private func bigTile(_ info: SourceInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                SourceIconView(sourceId: info.sourceId, imageUrl: info.iconUrl, iconSize: 50)
                Spacer(minLength: 0)
                if model.hasUpdate(info) {
                    Text("Update")
                        .font(.mdMono(10, weight: .bold)).textCase(.uppercase).tracking(0.6)
                        .foregroundStyle(Color.mdAccent)
                        .padding(.horizontal, 6).frame(height: 20)
                        .background(Color.mdAccentSoft)
                }
            }
            Text(info.name)
                .font(.mdDisplay(18, weight: .bold))
                .foregroundStyle(Color.mdText)
                .lineLimit(1)
                .padding(.top, 12)
            Text(info.disabled ? "Disabled" : "\(languageLabel(info.languages)) · \(info.languages.filter { $0 != "multi" }.count) languages")
                .font(.mdSystem(size: 11.5)).foregroundStyle(Color.mdText3).lineLimit(1)
                .padding(.top, 2)
            HStack(spacing: 4) {
                Text("Browse")
                Image(systemName: "arrow.right").font(.system(size: 12, weight: .bold))
            }
            .font(.mdSystem(size: 13, weight: .semibold))
            .foregroundStyle(Color.mdAccent)
            .padding(.top, 12)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topTrailing) {
            Circle().fill(Color.mdAccent).frame(width: 140, height: 140).blur(radius: 44).opacity(0.35).offset(x: 50, y: -50)
        }
        .background(Color.mdS1)
        .clipped()
        .overlay(Rectangle().strokeBorder(Color.mdLine, lineWidth: 1))
        .opacity(info.disabled ? 0.5 : 1)
        .contentShape(Rectangle())
    }

    // `.tile`
    private func tile(_ info: SourceInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                SourceIconView(sourceId: info.sourceId, imageUrl: info.iconUrl, iconSize: 42)
                Spacer(minLength: 0)
                if model.busy.contains(info.sourceId) {
                    ProgressView().controlSize(.mini)
                } else if model.hasUpdate(info) {
                    Rectangle().fill(Color.mdAccent).frame(width: 9, height: 9)
                        .accessibilityLabel("Update available")
                }
            }
            Text(info.name)
                .font(.mdSystem(size: 14, weight: .semibold))
                .foregroundStyle(Color.mdText)
                .lineLimit(1)
                .padding(.top, 12)
            Text(info.disabled ? "Disabled" : "\(languageLabel(info.languages)) · v\(info.version)")
                .font(.mdSystem(size: 11.5)).foregroundStyle(Color.mdText3).lineLimit(1)
                .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.mdS1)
        .overlay(Rectangle().strokeBorder(Color.mdLine, lineWidth: 1))
        .opacity(info.disabled ? 0.5 : 1)
        .contentShape(Rectangle())
    }

    private func availableTile(_ info: ExternalSourceInfo) -> some View {
        let languages = info.languages ?? [info.lang ?? ""]
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                SourceIconView(sourceId: info.id, imageUrl: info.toInfo().iconUrl, iconSize: 42)
                Spacer(minLength: 0)
                if info.resolvedContentRating == .containsNsfw {
                    Text("18+").font(.mdSystem(size: 12, weight: .medium)).foregroundStyle(Color.mdText2)
                        .padding(.horizontal, 6).frame(height: 22)
                        .overlay(Rectangle().strokeBorder(Color.mdLine2, lineWidth: 1))
                }
            }
            Text(info.name)
                .font(.mdSystem(size: 14, weight: .semibold))
                .foregroundStyle(Color.mdText)
                .lineLimit(1)
                .padding(.top, 12)
            Text("\(languageLabel(languages)) · v\(info.version)")
                .font(.mdSystem(size: 11.5)).foregroundStyle(Color.mdText3).lineLimit(1)
                .padding(.top, 2)
            Button {
                Task {
                    if !(await model.install(info)) { failedInstall = info.name }
                }
            } label: {
                HStack(spacing: 5) {
                    if model.busy.contains(info.id) {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.down").font(.system(size: 12, weight: .bold))
                        Text("Install")
                    }
                }
                .font(.mdSystem(size: 13, weight: .semibold))
                .foregroundStyle(Color.mdText)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .overlay(Rectangle().strokeBorder(Color.mdLine2, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.busy.contains(info.id))
            .padding(.top, 10)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.mdS1)
        .overlay(Rectangle().strokeBorder(Color.mdLine, lineWidth: 1))
    }

    private func emptyState(title: String, detail: String, action: String? = nil, perform: (() -> Void)? = nil) -> some View {
        VStack(spacing: 10) {
            Text(title).font(.mdDisplay(19, weight: .bold)).foregroundStyle(Color.mdText)
            Text(detail).font(.mdSystem(size: 14)).foregroundStyle(Color.mdText3).multilineTextAlignment(.center)
            if let action, let perform {
                Button(action, action: perform).buttonStyle(MDGhostButtonStyle(small: false)).padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.top, 48)
    }
}
