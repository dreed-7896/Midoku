import Testing
import UIKit
@testable import Midoku

@MainActor
@Suite("Artwork persistence and reader controls", .serialized)
struct ArtworkCacheTests {
    @Test func artworkSurvivesRecreationWithoutSourceAccess() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = MCArtworkCache(directory: directory)
        let key = MCArtworkCache.key(url: "https://blocked.invalid/cover.jpg", sourceKey: "test-source")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 30)).image { context in
            UIColor.systemPink.setFill(); context.fill(CGRect(x: 0, y: 0, width: 20, height: 30))
        }
        cache.store(image: image, for: key, revision: cache.revision(for: key))
        await cache.flush()
        let restarted = MCArtworkCache(directory: directory)
        let restored = try #require(await restarted.image(for: key))
        #expect(restored.image.cgImage?.width == image.cgImage?.width)
        #expect(restored.image.cgImage?.height == image.cgImage?.height)
        #expect(restarted.memoryImage(for: key) != nil)
        #expect(key != MCArtworkCache.key(url: "https://blocked.invalid/cover.jpg", sourceKey: "other-source"))
    }

    @Test func resetRejectsAnOldRequestAndRemovesDiskArtwork() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = MCArtworkCache(directory: directory)
        let key = MCArtworkCache.key(url: "https://blocked.invalid/thumbnail.jpg", sourceKey: "test")
        let revision = cache.revision(for: key)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { _ in }
        cache.store(image: image, for: key, revision: revision)
        cache.reset(key)
        #expect(cache.store(image: image, for: key, revision: revision) == nil)
        #expect(await cache.image(for: key) == nil)
        #expect(cache.needsReload(for: key))
        cache.store(image: image, for: key, revision: cache.revision(for: key))
        #expect(!cache.needsReload(for: key))
        cache.removeAll()
        #expect(await cache.image(for: key) == nil)
    }

    @Test func chapterButtonsAndPageSliderShareACenterLine() {
        let controls = ReaderToolbarView()
        controls.frame = CGRect(x: 0, y: 0, width: 320, height: 62)
        controls.layoutIfNeeded()
        #expect(abs(controls.previousChapterButton.center.y - controls.sliderView.center.y) < 0.5)
        #expect(abs(controls.nextChapterButton.center.y - controls.sliderView.center.y) < 0.5)
        #expect(controls.sliderView.frame.minX >= controls.previousChapterButton.frame.maxX)
        #expect(controls.sliderView.frame.maxX <= controls.nextChapterButton.frame.minX)
    }
}
