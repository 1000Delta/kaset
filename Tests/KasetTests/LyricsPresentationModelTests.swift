import Foundation
import Testing
@testable import Kaset

// MARK: - LyricsPresentationModelTests

@MainActor
struct LyricsPresentationModelTests {
    @Test func noDemandDoesNotFetch() async {
        let gate = LyricsLoadGate()
        let model = Self.model(gate)
        model.updateTrack(Self.info("A"), syncedEnabled: true)
        await Self.settle()
        #expect(gate.requests.isEmpty)
        #expect(!model.isLoading)
    }

    @Test func twoConsumersShareOneFlightAndReopeningUsesResult() async {
        let gate = LyricsLoadGate()
        let model = Self.model(gate)
        model.updateTrack(Self.info("A"), syncedEnabled: true)
        let first = UUID(), second = UUID()
        model.setDemand(first, active: true)
        model.setDemand(second, active: true)
        await Self.settle()
        #expect(gate.requests == ["A:true"])
        gate.finish("A:true", with: .plain(Lyrics(text: "A", source: nil)))
        await Self.settle()
        #expect(!model.isLoading)
        model.setDemand(first, active: false)
        model.setDemand(second, active: false)
        model.setDemand(first, active: true)
        await Self.settle()
        #expect(gate.requests.count == 1)
        #expect(model.currentLyrics == .plain(Lyrics(text: "A", source: nil)))
    }

    @Test func staleACompletionCannotOverwriteBOrEndItsLoading() async {
        let gate = LyricsLoadGate()
        let model = Self.model(gate)
        model.setDemand(UUID(), active: true)
        model.updateTrack(Self.info("A"), syncedEnabled: true)
        await Self.settle()
        model.updateTrack(Self.info("B"), syncedEnabled: true)
        #expect(model.currentLyrics == .unavailable)
        await Self.settle()
        gate.finish("A:true", with: .plain(Lyrics(text: "stale", source: nil)))
        await Self.settle()
        #expect(model.isLoading)
        #expect(model.currentLyrics == .unavailable)
        gate.finish("B:true", with: .plain(Lyrics(text: "B", source: nil)))
        await Self.settle()
        #expect(!model.isLoading)
        #expect(model.currentLyrics == .plain(Lyrics(text: "B", source: nil)))
    }

    @Test func clearingTrackInvalidatesPendingCompletionAndLoading() async {
        let gate = LyricsLoadGate()
        let model = Self.model(gate)
        model.setDemand(UUID(), active: true)
        model.updateTrack(Self.info("A"), syncedEnabled: true)
        await Self.settle()
        model.updateTrack(nil, syncedEnabled: true)
        gate.finish("A:true", with: .synced(LyricsDemandCoordinatorTests.lyrics()))
        await Self.settle()
        #expect(model.currentLyrics == .unavailable)
        #expect(!model.isLoading)
        #expect(model.videoId == nil)
    }

    @Test func syncedSettingChangeInvalidatesOldRequest() async {
        let gate = LyricsLoadGate()
        let model = Self.model(gate)
        model.setDemand(UUID(), active: true)
        model.updateTrack(Self.info("A"), syncedEnabled: true)
        await Self.settle()
        model.updateTrack(Self.info("A"), syncedEnabled: false)
        await Self.settle()
        #expect(gate.requests == ["A:true", "A:false"])
        gate.finish("A:false", with: .plain(Lyrics(text: "plain", source: nil)))
        gate.finish("A:true", with: .synced(LyricsDemandCoordinatorTests.lyrics()))
        await Self.settle()
        #expect(model.currentLyrics == .plain(Lyrics(text: "plain", source: nil)))
        #expect(!model.isLoading)
    }

    @Test func suppressionImmediatelyClearsAndStopsPolling() async {
        let gate = LyricsLoadGate()
        var starts = 0, stops = 0
        let poll = LyricsDemandCoordinator(start: { _ in starts += 1 }, stop: { stops += 1 }, resetDisplay: {})
        let model = LyricsPresentationModel(polling: poll, load: gate.load)
        model.setDemand(UUID(), active: true)
        model.updateTrack(Self.info("A"), syncedEnabled: true)
        await Self.settle()
        gate.finish("A:true", with: .synced(LyricsDemandCoordinatorTests.lyrics()))
        await Self.settle()
        #expect(starts == 1)
        model.updateTrack(nil, syncedEnabled: true)
        #expect(stops == 1)
        #expect(model.currentLyrics == .unavailable)
    }

    @Test func refreshForWrongTrackIsIgnored() {
        let gate = LyricsLoadGate()
        let model = Self.model(gate)
        model.updateTrack(Self.info("B"), syncedEnabled: true)
        model.refreshLyrics(.synced(LyricsDemandCoordinatorTests.lyrics()), videoId: "A")
        #expect(model.currentLyrics == .unavailable)
    }

    private static func info(_ id: String) -> LyricsSearchInfo {
        LyricsSearchInfo(title: id, artist: "artist", album: nil, duration: nil, videoId: id)
    }

    private static func model(_ gate: LyricsLoadGate) -> LyricsPresentationModel {
        LyricsPresentationModel(polling: LyricsDemandCoordinator(start: { _ in }, stop: {}, resetDisplay: {}), load: gate.load)
    }

    private static func settle() async {
        for _ in 0 ..< 100 {
            await Task.yield()
        }
    }
}

// MARK: - LyricsLoadGate

@MainActor
private final class LyricsLoadGate {
    var requests: [String] = []
    var pending: [String: CheckedContinuation<LyricResult, Never>] = [:]

    func load(_ info: LyricsSearchInfo, _ syncedEnabled: Bool) async -> LyricResult {
        let key = "\(info.videoId):\(syncedEnabled)"
        self.requests.append(key)
        return await withCheckedContinuation { self.pending[key] = $0 }
    }

    func finish(_ key: String, with result: LyricResult) {
        self.pending.removeValue(forKey: key)?.resume(returning: result)
    }
}
