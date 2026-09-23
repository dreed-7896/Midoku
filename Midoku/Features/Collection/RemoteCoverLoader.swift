import AidokuRunner
import Foundation
import Nuke
import UIKit

@MainActor
enum MCRemoteCoverLoader {
    static func load(
        _ value: String,
        source: AidokuRunner.Source?
    ) async throws -> MCLibraryCover {
        guard let url = MCRemoteCoverURL.parse(value) else { throw MCLibraryFailure.coverURL }

        let urlRequest = if let source {
            await source.getModifiedImageRequest(url: url, context: nil)
        } else {
            URLRequest(url: url)
        }
        var processors: [ImageProcessing] = []
        if let source, source.features.processesPages {
            processors.append(PageInterceptorProcessor(source: source, pageContext: nil))
        } else if let source, source.features.processesCovers {
            processors.append(CoverInterceptorProcessor(source: source))
        }
        let request = ImageRequest(
            urlRequest: urlRequest,
            processors: processors,
            userInfo: [.processesKey: !processors.isEmpty]
        )
        // Validate the URL, but let Nuke own the image bytes in its clearable cache.
        _ = try await ImagePipeline.shared.image(for: request)
        return MCLibraryCover(url: url, sourceKey: source?.key, pageImage: source?.features.processesPages == true)
    }
}
