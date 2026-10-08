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

    @State private var imageRequest: ImageRequest?
    @State private var artwork: MCArtworkCache.Artwork?
    @State private var loadedKey: String?
    @State private var cacheRevision = ""

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
        LazyImage(
            request: imageRequest,
            transaction: .init(animation: nil)
        ) { state in
            if state.imageContainer?.type == .gif, let data = state.imageContainer?.data {
                GIFImage(
                    data: data,
                    contentMode: contentMode
                )
                    .frame(width: width, height: height)
                    .id(state.image != nil ? imageUrl : "placeholder") // ensures only opacity is animated
            } else if state.image == nil, let placeholderSymbol {
                Image(systemName: placeholderSymbol)
                    .font(.title3).foregroundStyle(.tertiary)
                    .frame(width: width, height: height)
                    .background(Color(uiColor: .secondarySystemBackground))
            } else if let image = state.image {
                image
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(width: width, height: height)
                    .id(imageUrl)
            } else if ["MangaPlaceholder", "MidokuCoverPlaceholder", "MidokuChapterPlaceholder"].contains(placeholder) {
                MCArtworkPlaceholder().frame(width: width, height: height)
            } else {
                Image(placeholder).resizable().aspectRatio(contentMode: contentMode)
                    .frame(width: width, height: height)
            }
        }
        .processors(processors)
        .onDisappear(.lowerPriority)
        .onCompletion { result in
            guard case .success(let response) = result, loadedKey == cacheKey else { return }
            artwork = MCArtworkCache.shared.store(
                image: response.image,
                animatedData: response.container.type == .gif ? response.container.data : nil,
                for: cacheKey, revision: cacheRevision
            )
        }
        .id(cacheKey)
    }

    func loadImageRequest(url: String) async {
        let key = cacheKey
        loadedKey = key
        imageRequest = nil
        artwork = MCArtworkCache.shared.memoryImage(for: key)
        cacheRevision = MCArtworkCache.shared.revision(for: key)
        if artwork != nil { return }
        if let cached = await MCArtworkCache.shared.image(for: key) {
            guard !Task.isCancelled, key == cacheKey else { return }
            artwork = cached
            return
        }
        guard !Task.isCancelled, key == cacheKey else { return }
        let url = URL(string: url)
        if let fileUrl = url?.toMidokuFileUrl() {
            imageRequest = ImageRequest(url: fileUrl)
            return
        }
        guard let source, let url, !url.isFileURL else {
            imageRequest = ImageRequest(url: url, options: MCArtworkCache.shared.needsReload(for: key) ? .reloadIgnoringCachedData : [])
            return
        }
        let request = await source.getModifiedImageRequest(url: url, context: nil)
        guard !Task.isCancelled, key == cacheKey else { return }
        imageRequest = ImageRequest(
            urlRequest: request,
            options: MCArtworkCache.shared.needsReload(for: key) ? .reloadIgnoringCachedData : [],
            userInfo: [.processesKey: (pageImage && source.features.processesPages) || source.features.processesCovers]
        )
    }
}
