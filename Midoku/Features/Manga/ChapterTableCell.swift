//
//  ChapterTableCell.swift
//  Midoku
//
//  Created by Skitty on 8/17/23.
//

import AidokuRunner
import SwiftUI

struct ChapterTableCell: View {
    let source: AidokuRunner.Source?
    let sourceKey: String
    let chapter: AidokuRunner.Chapter
    let read: Bool
    let page: Int?
    let totalPages: Int?
    let alwaysShowPageCount: Bool
    let fallbackThumbnail: String?
    let downloadStatus: DownloadStatus
    var downloadProgress: Float?
    let displayMode: ChapterTitleDisplayMode

    var downloaded: Bool {
        downloadStatus == .finished
    }

    /// A download that stopped with pages missing, which is neither downloaded nor in progress.
    var downloadFailed: Bool {
        downloadStatus == .failed
    }

    var locked: Bool {
        chapter.locked && !downloaded
    }

    var progress: Float? {
        downloadProgress ?? (downloadStatus == .queued || downloadStatus == .downloading ? 0 : nil)
    }

    /// Started but not finished: the chapter you'd continue with.
    var inProgress: Bool {
        !read && (page ?? 0) > 0
    }

    var body: some View {
        let isNew = !read && (chapter.dateUploaded.map { $0 > Date.now.addingTimeInterval(-7 * 86_400) } ?? false)
        MDChapterRow(
            label: chapter.formattedTitle(forceMode: displayMode),
            meta: chapter.formattedSubtitle(
                page: page,
                totalPages: totalPages,
                alwaysShowPageCount: alwaysShowPageCount,
                sourceKey: sourceKey
            ).map { read ? "Read · \($0)" : $0 } ?? (read ? "Read" : nil),
            read: read || locked,
            current: inProgress,
            progress: inProgress ? totalPages.map { Double(page ?? 0) / Double(max(1, $0)) } : nil
        ) {
            if isNew { MDRowBadge(text: "New") }
        } trailing: {
            if downloaded {
                MDFlag(systemImage: "arrow.down")
            } else if downloadFailed {
                Image(systemName: "exclamationmark.circle.fill").imageScale(.small).foregroundStyle(Color(uiColor: MDColor.amber))
            } else if let progress {
                DownloadProgressView(progress: progress)
                    .frame(width: 13, height: 13)
            } else if locked {
                MDFlag(systemImage: "lock.fill")
            }
        }
        .padding(.horizontal, 16)
    }
}

private struct DownloadProgressView: UIViewRepresentable {
    var progress: Float

    func makeUIView(context: Context) -> CircularProgressView {
        let progressView = CircularProgressView(frame: CGRect(x: 0, y: 0, width: 13, height: 13))
        progressView.radius = 13 / 2
        progressView.trackColor = .quaternaryLabel
        progressView.progressColor = progressView.tintColor
        return progressView
    }

    func updateUIView(_ uiView: CircularProgressView, context: Context) {
        uiView.setProgress(value: progress, withAnimation: false)
    }
}
