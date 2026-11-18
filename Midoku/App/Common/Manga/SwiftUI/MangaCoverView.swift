//
//  MangaCoverView.swift
//  Midoku
//
//  Created by Skitty on 9/8/23.
//

import AidokuRunner
import SwiftUI
import Nuke
import NukeUI

struct MangaCoverView: View {
    var source: AidokuRunner.Source?

    let coverImage: String
    var width: CGFloat?
    var height: CGFloat?
    var downsampleWidth: CGFloat?
    var contentMode: ContentMode = .fill
    var placeholder = "MangaPlaceholder"
    var bookmarked: Bool = false
    var title: String?

    var body: some View {
        SourceImageView(
            source: source,
            imageUrl: coverImage,
            width: width,
            height: height,
            downsampleWidth: downsampleWidth,
            contentMode: contentMode,
            placeholder: placeholder,
            placeholderTitle: title
        )
        .overlay(alignment: .topLeading) { bookmarkView }
        .clipShape(Rectangle())
        .overlay(Rectangle().strokeBorder(Color.mdLine, lineWidth: 1))
    }

    /// `.badge--tl.badge--glass`: "✓ Saved" on titles already in the library.
    @ViewBuilder
    var bookmarkView: some View {
        if bookmarked { Self.savedBadge }
    }

    static var savedBadge: some View {
            HStack(spacing: 4) {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy))
                Text("Saved").font(.mdMono(11, weight: .bold)).textCase(.uppercase).tracking(0.3)
            }
            .foregroundStyle(Color.mdText)
            .padding(.horizontal, 6)
            .frame(height: 22)
            .background(Color.black.opacity(0.62))
    }
}
