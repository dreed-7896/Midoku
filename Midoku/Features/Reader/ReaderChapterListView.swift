//
//  ReaderChapterListView.swift
//  Midoku (iOS)
//
//  Created by Skitty on 12/20/22.
//

import SwiftUI
import AidokuRunner

struct ReaderChapterListView: View {
    var chapterList: [AidokuRunner.Chapter]
    @State var chapter: AidokuRunner.Chapter
    var collectionSequence: MCReaderSequence? = nil
    var chapterSet: ((AidokuRunner.Chapter) -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PlatformNavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(chapterList) { chapter in
                            Button {
                                self.chapter = chapter
                                chapterSet?(chapter)
                            } label: {
                                let source = collectionSequence?.route(chapter).map { $0.source?.name ?? $0.manga.sourceKey }
                                let subtitle = chapter.chapterNumber != nil || chapter.volumeNumber != nil ? chapter.title : nil
                                MDChapterRow(
                                    label: displayString(for: chapter),
                                    meta: [subtitle, source].compactMap { $0 }.joined(separator: " · "),
                                    current: chapter == self.chapter
                                ) {
                                    if chapter == self.chapter { MDFlag(systemImage: "book.fill", accent: true) }
                                }
                            }
                            .buttonStyle(.plain)
                            .id(chapter.id)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .background(Color.mdBg)
                .onAppear {
                    proxy.scrollTo(chapter.id, anchor: .center)
                }
            }
            .navigationTitle(NSLocalizedString("CHAPTERS"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton {
                        dismiss()
                    }
                }
            }
        }
    }

    private func displayString(for chapter: AidokuRunner.Chapter) -> String {
        if let chapterNum = chapter.chapterNumber {
            if let volumeNum = chapter.volumeNumber {
                String(
                    format: NSLocalizedString("VOL_X") + " " + NSLocalizedString("CH_X"),
                    volumeNum,
                    chapterNum
                )
            } else {
                String(format: NSLocalizedString("CHAPTER_X"), chapterNum)
            }
        } else if let volumeNum = chapter.volumeNumber {
            String(format: NSLocalizedString("VOLUME_X"), volumeNum)
        } else {
            chapter.title ?? ""
        }
    }
}
