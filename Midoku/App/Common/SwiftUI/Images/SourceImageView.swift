//
//  SourceImageView.swift
//  Midoku
//
//  Created by Skitty on 4/26/25.
//

import AidokuRunner
import Nuke
import NukeUI
import SwiftUI

struct SourceImageView: View {
    var source: AidokuRunner.Source?

    let imageUrl: String
    var width: CGFloat?
    var height: CGFloat?
    var downsampleWidth: CGFloat?
    var contentMode: ContentMode = .fill
    var placeholder = "MangaPlaceholder"
    var placeholderSymbol: String?
    var pageImage = false

    @State private var artwork: MCArtworkCache.Artwork?
    @State private var loadedKey: String?

    private var cacheKey: String {
        MCArtworkCache.key(url: imageUrl, sourceKey: source?.key, pageImage: pageImage, width: downsampleWidth)
    }

    private var processors: [ImageProcessing] {
        var processors: [ImageProcessing] = []
        if let downsampleWidth {
            processors.append(DownsampleProcessor(width: downsampleWidth))
        }
        if pageImage, let source, source.features.processesPages {
            processors.append(PageInterceptorProcessor(source: source, pageContext: nil))
        } else if let source, source.features.processesCovers {
            processors.append(CoverInterceptorProcessor(source: source))
        }
        return processors
    }

    var body: some View {
        Group {
            if let cached = (loadedKey == cacheKey ? artwork : nil) ?? MCArtworkCache.shared.memoryImage(for: cacheKey) {
                if let data = cached.animatedData {
                    GIFImage(data: data, contentMode: contentMode).frame(width: width, height: height)
                } else {
                    Image(uiImage: cached.image).resizable().aspectRatio(contentMode: contentMode)
                        .frame(width: width, height: height)
                }
            } else {
                remoteImage
            }
        }
        .clipped()
        .contentShape(Rectangle())
        .task(id: cacheKey) { await loadImageRequest(url: imageUrl) }
    }

    private var remoteImage: some View {
        Group {
            if let placeholderSymbol {
                Image(systemName: placeholderSymbol).font(.title3).foregroundStyle(.tertiary)
                    .frame(width: width, height: height).background(Color(uiColor: .secondarySystemBackground))
            } else if ["MangaPlaceholder", "MidokuCoverPlaceholder", "MidokuChapterPlaceholder"].contains(placeholder) {
                MCArtworkPlaceholder().frame(width: width, height: height)
            } else {
                Image(placeholder).resizable().aspectRatio(contentMode: contentMode).frame(width: width, height: height)
            }
        }
    }

    func loadImageRequest(url: String) async {
        let key = cacheKey
        loadedKey = key
        if let cached = MCArtworkCache.shared.memoryImage(for: key) { artwork = cached; return }
        let source = source
        let processors = processors
        let pageImage = pageImage
        let loaded = await MCArtworkCache.shared.load(key: key) {
            guard let url = URL(string: url) else { return nil }
            let options: ImageRequest.Options = MCArtworkCache.shared.needsReload(for: key) ? .reloadIgnoringCachedData : []
            if let fileURL = url.toMidokuFileUrl() { return ImageRequest(url: fileURL, processors: processors, options: options) }
            let request = if let source, !url.isFileURL {
                await source.getModifiedImageRequest(url: url, context: nil)
            } else { URLRequest(url: url) }
            return ImageRequest(urlRequest: request, processors: processors, options: options,
                userInfo: [.processesKey: (pageImage && source?.features.processesPages == true) || source?.features.processesCovers == true])
        }
        guard !Task.isCancelled, key == cacheKey else { return }
        artwork = loaded
    }
}
