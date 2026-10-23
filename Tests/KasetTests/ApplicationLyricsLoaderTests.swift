import Foundation
import Testing
@testable import Kaset

// MARK: - ApplicationLyricsLoaderTests

@MainActor
struct ApplicationLyricsLoaderTests {
    @Test func syncedDisabledAppliesPlainFallbackWithoutAskingProviders() async {
        let provider = LoaderLyricsProvider(result: .synced(LyricsDemandCoordinatorTests.lyrics()))
        let service = SyncedLyricsService(providers: [provider], displayLyrics: { $0 })
        service.clearLyrics(for: "A")
        let loader = ApplicationLyricsLoader(service: service) { videoId in
            Lyrics(text: "Plain \(videoId)", source: "Test")
        }

        let result = await loader.load(Self.info("A"), syncedEnabled: false)

        #expect(result == .plain(Lyrics(text: "Plain A", source: "Test")))
        #expect(await provider.callCount() == 0)
    }

    @Test func plainFailureLeavesLyricsUnavailable() async {
        struct Offline: Error {}
        let service = SyncedLyricsService(providers: [], displayLyrics: { $0 })
        service.clearLyrics(for: "A")
        let loader = ApplicationLyricsLoader(service: service) { _ in throw Offline() }

        let result = await loader.load(Self.info("A"), syncedEnabled: false)

        #expect(result == .unavailable)
        #expect(!service.isLoading)
    }

    @Test func plainResultForAReplacedTrackIsRejected() async {
        let service = SyncedLyricsService(providers: [], displayLyrics: { $0 })
        service.clearLyrics(for: "A")
        let loader = ApplicationLyricsLoader(service: service) { _ in
            // The track changed while the plain-lyrics request was in flight.
            service.clearLyrics(for: "B")
            return Lyrics(text: "stale", source: nil)
        }

        let result = await loader.load(Self.info("A"), syncedEnabled: false)

        #expect(result == .unavailable)
        #expect(service.currentVideoId == "B")
    }

    private static func info(_ id: String) -> LyricsSearchInfo {
        LyricsSearchInfo(title: id, artist: "artist", album: nil, duration: nil, videoId: id)
    }
}

// MARK: - LoaderLyricsProvider

private final class LoaderLyricsProvider: LyricsProvider, @unchecked Sendable {
    let name = "LoaderProvider"
    private let result: LyricResult
    private let counter = LoaderCallCounter()

    init(result: LyricResult) {
        self.result = result
    }

    func search(info _: LyricsSearchInfo) async -> LyricResult {
        await self.counter.increment()
        return self.result
    }

    func callCount() async -> Int {
        await self.counter.value
    }
}

// MARK: - LoaderCallCounter

private actor LoaderCallCounter {
    private(set) var value = 0

    func increment() {
        self.value += 1
    }
}
