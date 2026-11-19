//
//  MangaCollectionViewController.swift
//  Midoku
//
//  Created by Skitty on 11/19/25.
//

import AidokuRunner
import Combine
import SwiftUI

class MangaCollectionViewController: BaseCollectionViewController {
    var usesListLayout = false
    /// Midoku Web `.grid3` of `.card`s (titles under the covers) instead of titles over the covers.
    var usesCardLayout = false

    lazy var dataSource = makeDataSource()
    lazy var refreshControl = UIRefreshControl()
    lazy var errorView = SourceErrorView()

    var entries: [AidokuRunner.Manga] = []
    var bookmarkedItems: Set<String> = []

    struct SkeletonView: View {
        let usesListLayout: Bool

        var body: some View {
            if usesListLayout {
                PlaceholderMangaHomeList.mainView(itemCount: 10)
                    .redacted(reason: .placeholder)
                    .shimmering()
            } else {
                HomeGridView.placeholder
            }
        }
    }
    lazy var skeletonViewController = {
        let hostingController = UIHostingController(rootView: SkeletonView(usesListLayout: usesListLayout))
        hostingController.view.backgroundColor = .clear
        hostingController.view.clipsToBounds = false
        return hostingController
    }()

    override func configure() {
        super.configure()
        collectionView.dataSource = dataSource
        collectionView.contentInset = UIEdgeInsets(
            top: 0,
            left: 0,
            bottom: 10,
            right: 0
        )
        collectionView.keyboardDismissMode = .onDrag

        // pull to refresh
        refreshControl.addTarget(self, action: #selector(refresh(_:)), for: .valueChanged)
        collectionView.refreshControl = refreshControl

        errorView.hide(animated: false)
        view.addSubview(errorView)

        addChild(skeletonViewController)
        collectionView.addSubview(skeletonViewController.view)
        skeletonViewController.didMove(toParent: self)
    }

    override func constrain() {
        super.constrain()

        errorView.translatesAutoresizingMaskIntoConstraints = false
        skeletonViewController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            errorView.topAnchor.constraint(equalTo: view.topAnchor),
            errorView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            errorView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            errorView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            skeletonViewController.view.topAnchor.constraint(equalTo: collectionView.safeAreaLayoutGuide.topAnchor),
            skeletonViewController.view.bottomAnchor.constraint(equalTo: collectionView.bottomAnchor),
            skeletonViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            skeletonViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    override func observe() {
        super.observe()

        addObserver(forName: .addToLibrary) { [weak self] notification in
            guard
                let self,
                let id = notification.object as? MangaIdentifier,
                let index = self.entries.firstIndex(where: { $0.identifier == id }),
                let entry = self.dataSource.itemIdentifier(for: IndexPath(item: index, section: 0))
            else {
                return
            }
            if self.bookmarkedItems.insert(entry.key).inserted {
                var snapshot = self.dataSource.snapshot()
                snapshot.reloadItems([entry])
                self.dataSource.apply(snapshot)
            }
        }

        addObserver(forName: .removeFromLibrary) { [weak self] notification in
            guard
                let self,
                let id = notification.object as? MangaIdentifier,
                let index = self.entries.firstIndex(where: { $0.identifier == id }),
                let entry = self.dataSource.itemIdentifier(for: IndexPath(item: index, section: 0))
            else {
                return
            }
            if self.bookmarkedItems.remove(entry.key) != nil {
                var snapshot = self.dataSource.snapshot()
                snapshot.reloadItems([entry])
                self.dataSource.apply(snapshot)
            }
        }
    }

    // MARK: Collection View Layout
    override func makeCollectionViewLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { sectionIndex, environment in
            switch Section(rawValue: sectionIndex) {
                case .regular:
                    if self.usesListLayout {
                        return OldMangaCollectionViewController.makeListLayoutSection(environment: environment)
                    } else if self.usesCardLayout {
                        return Self.makeCardLayoutSection(environment: environment)
                    } else {
                        return OldMangaCollectionViewController.makeGridLayoutSection(environment: environment)
                    }
                case nil:
                    return nil
            }
        }
    }
}

extension MangaCollectionViewController {
    /// `.grid3`: three columns on a phone (more on wider screens), 10pt apart, rows 18pt apart.
    static func makeCardLayoutSection(environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        let containerWidth = environment.container.contentSize.width
        let usable = containerWidth - 32
        let columns = max(3, Int(floor((usable + 10) / 140)))
        let itemWidth = (usable - CGFloat(columns - 1) * 10) / CGFloat(columns)
        let itemHeight = (itemWidth * 1.5 + 8 + 34).rounded(.up)
        let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
            widthDimension: .absolute(itemWidth),
            heightDimension: .absolute(itemHeight)
        ))
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(itemHeight)),
            subitem: item,
            count: columns
        )
        group.interItemSpacing = .fixed(10)
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 0, trailing: 16)
        section.interGroupSpacing = 18
        return section
    }

    @objc func refresh(_ control: UIRefreshControl) {
        control.endRefreshing()
    }

    func hideLoadingView() {
        UIView.animate(withDuration: CATransaction.animationDuration()) {
            self.skeletonViewController.view.alpha = 0
        } completion: { _ in
            self.skeletonViewController.view.removeFromSuperview()
            self.skeletonViewController.removeFromParent()
        }
    }
}

extension MangaCollectionViewController {
    // MARK: Cell Registration
    typealias GridCellRegistration = UICollectionView.CellRegistration<MangaGridCell, AidokuRunner.Manga>
    typealias ListCellRegistration = UICollectionView.CellRegistration<MangaListCell, AidokuRunner.Manga>

    func makeGridCellRegistration() -> GridCellRegistration {
        GridCellRegistration { [weak self] cell, _, manga in
            cell.identifier = MangaIdentifier(sourceKey: manga.sourceKey, mangaKey: manga.key)
            cell.titleBelow = self?.usesCardLayout ?? false
            cell.title = manga.title
            cell.showsBookmark = self?.bookmarkedItems.contains(manga.key) ?? false
            Task {
                await cell.loadImage(url: manga.cover.flatMap { URL(string: $0) })
            }
        }
    }

    func makeListCellRegistration() -> ListCellRegistration {
        ListCellRegistration { [weak self] cell, _, manga in
            cell.configure(with: manga, isBookmarked: self?.bookmarkedItems.contains(manga.key) ?? false)
        }
    }

    // MARK: Data Source
    enum Section: Int, CaseIterable {
        case regular
    }

    func makeDataSource() -> UICollectionViewDiffableDataSource<Section, AidokuRunner.Manga> {
        if usesListLayout {
            UICollectionViewDiffableDataSource(
                collectionView: collectionView,
                cellProvider: makeListCellRegistration().cellProvider
            )
        } else {
            UICollectionViewDiffableDataSource(
                collectionView: collectionView,
                cellProvider: makeGridCellRegistration().cellProvider
            )
        }
    }

    func updateDataSource() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, AidokuRunner.Manga>()
        snapshot.appendSections([.regular])
        snapshot.appendItems(entries.unique(), toSection: .regular)
        dataSource.apply(snapshot)
    }

    func clearEntries() {
        dataSource.apply(.init())
    }
}

// MARK: UICollectionViewDelegate
extension MangaCollectionViewController {
    func collectionView(_ collectionView: UICollectionView, didHighlightItemAt indexPath: IndexPath) {
        let cell = collectionView.cellForItem(at: indexPath)
        if let cell = cell as? MangaGridCell {
            cell.highlight()
        } else if let cell = cell as? MangaListCell {
            cell.highlight()
        }
    }

    func collectionView(_ collectionView: UICollectionView, didUnhighlightItemAt indexPath: IndexPath) {
        let cell = collectionView.cellForItem(at: indexPath)
        if let cell = cell as? MangaGridCell {
            cell.unhighlight()
        } else if let cell = cell as? MangaListCell {
            cell.unhighlight()
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let manga = dataSource.itemIdentifier(for: indexPath) else {
            return
        }
        let viewController = MangaViewController(manga: manga, parent: self)
        if #available(iOS 18.0, *) {
            viewController.preferredTransition = .zoom { context in
                guard
                    let detailViewController = context.zoomedViewController as? MangaViewController,
                    let indexPath = self.dataSource.indexPath(for: detailViewController.manga),
                    let cell = self.collectionView.cellForItem(at: indexPath)
                else {
                    return nil
                }
                if let cell = cell as? MangaListCell {
                    return cell.coverImageView
                } else {
                    return cell.contentView
                }
            }
        }
        navigationController?.pushViewController(viewController, animated: true)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard indexPaths.count == 1, let indexPath = indexPaths.first,
              let entry = dataSource.itemIdentifier(for: indexPath)
        else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            return UIMenu(title: "", children: self.entryRows(entry).map(\.uiAction))
        }
    }

    private func entryRows(_ entry: AidokuRunner.Manga) -> [MDActionRow] {
        var rows: [MDActionRow] = []
        if entry.isLocal() {
            rows.append(MDActionRow(systemImage: "trash", title: NSLocalizedString("REMOVE"), destructive: true) {
                Task {
                    await LocalFileManager.shared.removeManga(with: entry.key)
                    NotificationCenter.default.post(name: .init("refresh-content"), object: nil)
                }
            })
        }
        if bookmarkedItems.contains(entry.key) {
            rows.append(MDActionRow(systemImage: "trash", title: NSLocalizedString("REMOVE_FROM_LIBRARY"), destructive: true) { [weak self] in
                guard let self else { return }
                let isTracking = TrackerManager.shared.isTracking(mangaId: entry.identifier)
                @MainActor
                func commit() {
                    self.bookmarkedItems.remove(entry.key)
                    var snapshot = self.dataSource.snapshot()
                    snapshot.reloadItems([entry])
                    self.dataSource.apply(snapshot)
                    Task { await MangaManager.shared.removeFromLibrary(mangaId: entry.identifier) }
                }
                if isTracking {
                    self.presentAlert(
                        title: NSLocalizedString("REMOVE_FROM_LIBRARY_CONFIRM"),
                        message: NSLocalizedString("REMOVE_FROM_LIBRARY_CONFIRM_TEXT"),
                        actions: [
                            UIAlertAction(title: NSLocalizedString("CANCEL"), style: .cancel),
                            UIAlertAction(title: NSLocalizedString("REMOVE"), style: .destructive) { _ in commit() }
                        ]
                    )
                } else {
                    commit()
                }
            })
        } else {
            rows.append(MDActionRow(systemImage: "plus.circle", title: NSLocalizedString("ADD_TO_LIBRARY")) { [weak self] in
                Task {
                    let source = await SourceManager.shared.source(for: entry.sourceKey)
                    let manga = (try? await source?.getMangaUpdate(manga: entry, needsDetails: true, needsChapters: true)) ?? entry
                    self?.present(UIHostingController(rootView: MCAddSourceView(manga: manga, chapters: manga.chapters ?? [])), animated: true)
                }
            })
        }
        return rows
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfiguration configuration: UIContextMenuConfiguration,
        highlightPreviewForItemAt indexPath: IndexPath
    ) -> UITargetedPreview? {
        guard
            let cell = collectionView.cellForItem(at: indexPath),
            cell is MangaListCell
        else {
            return nil
        }

        // add some padding to list cell
        let parameters = UIPreviewParameters()
        let padding: CGFloat = 8
        let rect = cell.bounds.insetBy(dx: -padding, dy: -padding)
        parameters.visiblePath = UIBezierPath(roundedRect: rect, cornerRadius: 0)

        return UITargetedPreview(view: cell.contentView, parameters: parameters)
    }
}
