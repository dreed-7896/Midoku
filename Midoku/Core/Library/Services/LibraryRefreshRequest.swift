import AidokuRunner
import Foundation

/// A source that ignores cancellation must not keep a refresh indicator alive forever.
/// Late results are discarded, and each request owns exactly one continuation.
@MainActor
final class LibraryRefreshRequest {
    private var continuation: CheckedContinuation<AidokuRunner.Manga, any Error>?
    private var request: Task<Void, Never>?
    private var timeout: Task<Void, Never>?

    static func fetch(source: AidokuRunner.Source, manga: AidokuRunner.Manga,
                      needsDetails: Bool, timeoutSeconds: Double = 45) async throws -> AidokuRunner.Manga {
        let operation = LibraryRefreshRequest()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                operation.continuation = continuation
                operation.request = Task {
                    do {
                        let result = try await source.getMangaUpdate(manga: manga, needsDetails: needsDetails, needsChapters: true)
                        operation.finish(.success(result))
                    } catch { operation.finish(.failure(error)) }
                }
                operation.timeout = Task {
                    do { try await Task.sleep(for: .seconds(timeoutSeconds)) }
                    catch { return }
                    operation.finish(.failure(URLError(.timedOut)))
                }
            }
        } onCancel: {
            Task { @MainActor in operation.finish(.failure(CancellationError())) }
        }
    }

    private func finish(_ result: Result<AidokuRunner.Manga, any Error>) {
        guard let continuation else { return }
        self.continuation = nil
        request?.cancel()
        timeout?.cancel()
        request = nil
        timeout = nil
        continuation.resume(with: result)
    }
}
