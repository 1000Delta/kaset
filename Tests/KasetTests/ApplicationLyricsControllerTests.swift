import Foundation
import Observation
import Testing
@testable import Kaset

// MARK: - ApplicationLyricsControllerTests

@MainActor
struct ApplicationLyricsControllerTests {
    @Test func launchObservationFetchesWithNoWindowOrPopover() async {
        let input = LyricsApplicationInput()
        let requests = LyricsApplicationRequests()
        let service = SyncedLyricsService(providers: [], displayLyrics: { $0 })
        let controller = Self.controller(input, requests, service)
        await Self.settle()
        #expect(requests.keys == ["A:true"])
        #expect(controller.model.isLoading)
        requests.finish("A:true", .synced(LyricsDemandCoordinatorTests.lyrics()))
        await Self.settle()
        #expect(controller.model.currentLyrics.isAvailable)
        input.videoId = "B"
        await Self.settle()
        #expect(requests.keys == ["A:true", "B:true"])
        #expect(controller.model.currentLyrics == .unavailable)
        requests.finish("B:true", .unavailable)
        await Self.settle()
    }

    @Test func optInChangesDemandWithoutRefetchingOtherConsumer() async {
        let input = LyricsApplicationInput()
        input.menuEnabled = false
        let requests = LyricsApplicationRequests()
        let service = SyncedLyricsService(providers: [], displayLyrics: { $0 })
        let controller = Self.controller(input, requests, service)
        await Self.settle()
        #expect(requests.keys.isEmpty)
        input.menuEnabled = true
        await Self.settle()
        #expect(requests.keys == ["A:true"])
        input.menuEnabled = false
        input.menuEnabled = true
        await Self.settle()
        #expect(requests.keys.count == 1)
        requests.finish("A:true", .unavailable)
        await Self.settle()
        #expect(!controller.model.isLoading)
    }

    @Test func adsVideoAndTrackNilClearWithoutViewCallbacks() async {
        let input = LyricsApplicationInput()
        let requests = LyricsApplicationRequests()
        let service = SyncedLyricsService(providers: [], displayLyrics: { $0 })
        let controller = Self.controller(input, requests, service)
        await Self.settle()
        input.isAd = true
        await Self.settle()
        requests.finish("A:true", .synced(LyricsDemandCoordinatorTests.lyrics()))
        await Self.settle()
        #expect(controller.model.videoId == nil)
        #expect(controller.model.currentLyrics == .unavailable)
        #expect(!controller.model.isLoading)
        input.isAd = false
        input.isMusic = false
        await Self.settle()
        #expect(requests.keys.count == 1)
        input.videoId = nil
        input.isMusic = true
        await Self.settle()
        #expect(controller.model.videoId == nil)
    }

    @Test func settingsInvalidatePendingApplicationRequest() async {
        let input = LyricsApplicationInput()
        let requests = LyricsApplicationRequests()
        let service = SyncedLyricsService(providers: [], displayLyrics: { $0 })
        let controller = Self.controller(input, requests, service)
        await Self.settle()
        input.syncedEnabled = false
        await Self.settle()
        #expect(requests.keys == ["A:true", "A:false"])
        requests.finish("A:true", .synced(LyricsDemandCoordinatorTests.lyrics()))
        await Self.settle()
        #expect(controller.model.isLoading)
        requests.finish("A:false", .plain(Lyrics(text: "plain", source: nil)))
        await Self.settle()
        #expect(controller.model.currentLyrics == .plain(Lyrics(text: "plain", source: nil)))
    }

    private static func controller(_ input: LyricsApplicationInput, _ requests: LyricsApplicationRequests, _ service: SyncedLyricsService) -> ApplicationLyricsController {
        ApplicationLyricsController(
            service: service,
            input: { input.snapshot },
            polling: LyricsDemandCoordinator(start: { _ in }, stop: {}, resetDisplay: {}),
            load: requests.load
        )
    }

    private static func settle() async {
        for _ in 0 ..< 150 {
            await Task.yield()
        }
    }
}

// MARK: - LyricsApplicationInput

@MainActor
@Observable
private final class LyricsApplicationInput {
    var videoId: String? = "A"
    var menuEnabled = true
    var syncedEnabled = true
    var isAd = false
    var isMusic = true

    var snapshot: LyricsPlaybackInput {
        LyricsPlaybackInput(
            track: self.videoId.map { LyricsSearchInfo(title: $0, artist: "artist", album: nil, duration: nil, videoId: $0) },
            isShowingAd: self.isAd, isMusicSource: self.isMusic,
            syncedEnabled: self.syncedEnabled, menuBarEnabled: self.menuEnabled
        )
    }
}

// MARK: - LyricsApplicationRequests

@MainActor
private final class LyricsApplicationRequests {
    var keys: [String] = []
    var pending: [String: CheckedContinuation<LyricResult, Never>] = [:]

    func load(_ info: LyricsSearchInfo, _ enabled: Bool) async -> LyricResult {
        let key = "\(info.videoId):\(enabled)"
        self.keys.append(key)
        return await withCheckedContinuation { self.pending[key] = $0 }
    }

    func finish(_ key: String, _ result: LyricResult) {
        self.pending.removeValue(forKey: key)?.resume(returning: result)
    }
}
