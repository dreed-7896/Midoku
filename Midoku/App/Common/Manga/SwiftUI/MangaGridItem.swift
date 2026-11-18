//
//  MangaGridItem.swift
//  Midoku
//
//  Created by Skitty on 8/16/23.
//

import AidokuRunner
import SwiftUI
import NukeUI

struct MangaGridItem: View {
    var source: AidokuRunner.Source?
    let title: String
    let coverImage: String
    var bookmarked: Bool = false

    static let gradient = Gradient(
        colors: (0...24).map { offset -> Color in
            let ratio = CGFloat(offset) / 24
            return Color.black.opacity(0.85 * pow(ratio, CGFloat(1.6)))
        }
    )

    var body: some View {
        let view = Rectangle()
            .fill(Color.clear)
            .aspectRatio(2/3, contentMode: .fill)
            .background {
                SourceImageView(
                    source: source,
                    imageUrl: coverImage,
                    downsampleWidth: 400 // reduces stuttering caused by rendering large images
                )
            }
            .overlay(
                LinearGradient(
                    gradient: Self.gradient,
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(alignment: .topLeading) { bookmarkView }
            .contentShape(RoundedRectangle(cornerRadius: 0))
            .clipShape(RoundedRectangle(cornerRadius: 0))
            .overlay(
                RoundedRectangle(cornerRadius: 0)
                    .strokeBorder(Color.mdLine, lineWidth: 1)
            )
            .overlay(
                Text(title)
                    .foregroundStyle(.white)
                    .font(.mdSystem(size: 13, weight: .semibold))
                    .multilineTextAlignment(.leading)
                    .lineLimit(5)
                    .shadow(color: .black.opacity(0.6), radius: 2)
                    .padding(8),
                alignment: .bottomLeading
            )
        if coverImage.hasSuffix("gif") {
            // if the image is a gif, we can't use drawingGroup (static image)
            view
        } else {
            view.drawingGroup()
        }
    }

    @ViewBuilder
    var bookmarkView: some View {
        if bookmarked {
            MangaCoverView.savedBadge
        }
    }

    static var placeholder: some View {
        Rectangle()
            .fill(Color.mdS2)
            .aspectRatio(2/3, contentMode: .fill)
    }
}

/// Midoku Web `.card`: the cover (2:3, hairline, "✓ Saved" badge) with a two-line title under it.
struct MDMangaCard: View {
    var source: AidokuRunner.Source?
    let title: String
    let coverImage: String
    var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(Color.mdS2)
                .aspectRatio(2/3, contentMode: .fill)
                .overlay {
                    SourceImageView(source: source, imageUrl: coverImage, downsampleWidth: 400)
                }
                .clipped()
                .overlay(alignment: .topLeading) { if saved { MangaCoverView.savedBadge } }
                .overlay(Rectangle().strokeBorder(Color.mdLine, lineWidth: 1))
                .contentShape(Rectangle())
            Text(title)
                .font(.mdSystem(size: 13, weight: .semibold))
                .foregroundStyle(Color.mdText)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
