import Foundation
import Testing
@testable import Kaset

// MARK: - SyncedLyricsLifecycleTests

@MainActor
struct SyncedLyricsLifecycleTests {
    @Test func simultaneousConsumersShareProviderSearch() async {
        let provider = LifecycleLyricsProvider()
        let service = SyncedLyricsService(providers: [provider], displayLyrics: { $0 })
        let info = Self.info("A")
        let first = Task { await service.fetchLyrics(for: info) }
        await Self.settle()
        let second = Task { await service.fetchLyrics(for: info) }
        await Self.settle()
        #expect(await provider.count == 1)
        await provider.finishAll(.unavailable)
        await first.value
        await second.value
        #expect(!service.isLoading)
    }

    @Test func newTrackClearsOldLyricsBeforeSearchCompletes() async {
        let provider = LifecycleLyricsProvider()
        let service = SyncedLyricsService(providers: [provider], displayLyrics: { $0 })
        let first = Task { await service.fetchLyrics(for: Self.info("A")) }
        await Self.settle()
        await provider.finishAll(.synced(LyricsDemandCoordinatorTests.lyrics()))
        await first.value
        let second = Task { await service.fetchLyrics(for: Self.info("B")) }
        await Self.settle()
        #expect(service.currentLyrics == .unavailable)
        #expect(service.isLoading)
        await provider.finishAll(.unavailable)
        await second.value
    }

    @Test func clearingDuringFetchRejectsCompletionAndStopsLoading() async {
        let provider = LifecycleLyricsProvider()
        let service = SyncedLyricsService(providers: [provider], displayLyrics: { $0 })
        let task = Task { await service.fetchLyrics(for: Self.info("A")) }
        await Self.settle()
        #expect(service.isLoading)
        service.clearLyrics()
        #expect(!service.isLoading)
        await provider.finishAll(.synced(LyricsDemandCoordinatorTests.lyrics()))
        await task.value
        #expect(service.currentLyrics == .unavailable)
        #expect(service.currentVideoId == nil)
        #expect(!service.isLoading)
    }

    @Test func staleFallbackCannotReplaceNewTrackResult() async {
        let provider = LifecycleLyricsProvider()
        let service = SyncedLyricsService(providers: [provider], displayLyrics: { $0 })
        let task = Task { await service.fetchLyrics(for: Self.info("B")) }
        await Self.settle()
        service.fallbackToPlainLyrics(Lyrics(text: "stale A", source: nil), videoId: "A")
        #expect(service.currentLyrics == .unavailable)
        await provider.finishAll(.unavailable)
        await task.value
    }

    @Test func clearingTrackRejectsLatePlainFallback() {
        let service = SyncedLyricsService(providers: [], displayLyrics: { $0 })
        service.clearLyrics()
        service.fallbackToPlainLyrics(Lyrics(text: "stale", source: nil), videoId: "A")
        #expect(service.currentLyrics == .unavailable)
        #expect(service.currentVideoId == nil)
    }

    @Test func selectedTrackAllowsPlainFallbackWithoutSyncedSearch() {
        let service = SyncedLyricsService(providers: [], displayLyrics: { $0 })
        service.clearLyrics(for: "A")
        service.fallbackToPlainLyrics(Lyrics(text: "plain", source: nil), videoId: "A")
        #expect(service.currentLyrics == .plain(Lyrics(text: "plain", source: nil)))
        #expect(service.currentVideoId == "A")
        service.clearLyrics(for: "B")
        service.fallbackToPlainLyrics(Lyrics(text: "stale", source: nil), videoId: "A")
        #expect(service.currentLyrics == .unavailable)
        #expect(service.currentVideoId == "B")
    }

    private static func info(_ id: String) -> LyricsSearchInfo {
        LyricsSearchInfo(title: id, artist: "artist", album: nil, duration: nil, videoId: id)
    }

    private static func settle() async {
        for _ in 0 ..< 100 {
            await Task.yield()
        }
    }
}

// MARK: - LifecycleLyricsProvider

private actor LifecycleLyricsProvider: LyricsProvider {
    nonisolated let name = "test"
    var count = 0
    private var pending: [CheckedContinuation<LyricResult, Never>] = []

    func search(info _: LyricsSearchInfo) async -> LyricResult {
        self.count += 1
        return await withCheckedContinuation { self.pending.append($0) }
    }

    func finishAll(_ result: LyricResult) {
        let pending = self.pending
        self.pending = []
        for continuation in pending {
            continuation.resume(returning: result)
        }
    }
}
