//
//  MangaUpdateItemView.swift
//  Midoku (iOS)
//
//  Created by axiel7 on 10/02/2024.
//

import AidokuRunner
import SwiftUI
import NukeUI

struct MangaUpdateItemView: View {
    private let coverWidth: CGFloat = 56
    private let coverHeight: CGFloat = 56
    private let cornerRadius: CGFloat = 0
    private let chaptersLimit = 5

    var updates: [MangaUpdatesView.UpdateInfo]

    private let manga: AidokuRunner.Manga?
    private let count: Int
    private let viewed: Bool

    init(updates: [MangaUpdatesView.UpdateInfo]) {
        self.updates = updates
        self.count = updates.count
        self.manga = updates.first?.manga
        self.viewed = updates.first?.viewed == true
    }

    var body: some View {
        HStack(spacing: 10) {
            MangaCoverView(
                source: manga.flatMap { SourceManager.shared.store.source(for: $0.sourceKey) },
                coverImage: manga?.cover ?? "",
                width: 38,
                height: 57
            )
            .clipped()

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    if !viewed { Rectangle().fill(Color.mdAccent).frame(width: 7, height: 7).accessibilityLabel("New") }
                    Text(manga?.title ?? "")
                        .font(.mdSystem(size: 15, weight: .semibold))
                        .foregroundStyle(Color.mdText)
                        .lineLimit(1)
                }
                let chapters = updates.prefix(chaptersLimit).compactMap { $0.chapter?.makeTitle() }
                Text(chapters.joined(separator: " · ") + (count > chaptersLimit ? " · " + String(format: NSLocalizedString("%lld_PLUS_MORE"), count - chaptersLimit) : ""))
                    .font(.mdSystem(size: 11.5))
                    .foregroundStyle(Color.mdText3)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if count > 1 {
                Text("+\(count)")
                    .font(.mdMono(10, weight: .bold))
                    .foregroundStyle(Color.mdAccent)
                    .padding(.horizontal, 6)
                    .frame(height: 20)
                    .background(Color.mdAccentSoft)
            }
        }
        .opacity(viewed ? 0.6 : 1)
        .padding(.vertical, 6)
    }
}
