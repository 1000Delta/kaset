import Foundation
import Testing
@testable import Kaset

// MARK: - LyricsDemandCoordinatorTests

@MainActor
struct LyricsDemandCoordinatorTests {
    @Test func independentLeasesKeepPollingUntilLastRelease() {
        let recorder = PollRecorder()
        let coordinator = recorder.coordinator()
        let sidebar = UUID(), menu = UUID()
        coordinator.updateLyrics(.synced(Self.lyrics()))
        coordinator.setDemand(sidebar, active: true)
        coordinator.setDemand(menu, active: true)
        coordinator.setDemand(sidebar, active: false)
        #expect(recorder.starts.count == 1)
        #expect(recorder.stops == 0)
        coordinator.setDemand(menu, active: false)
        #expect(recorder.stops == 1)
    }

    @Test func demandAndReleaseAreIdempotent() {
        let recorder = PollRecorder()
        let coordinator = recorder.coordinator()
        let lease = UUID()
        coordinator.updateLyrics(.synced(Self.lyrics()))
        coordinator.setDemand(lease, active: true)
        coordinator.setDemand(lease, active: true)
        coordinator.setDemand(lease, active: false)
        coordinator.setDemand(lease, active: false)
        #expect(recorder.starts.count == 1)
        #expect(recorder.stops == 1)
    }

    @Test func noDemandOrUnsyncedResultNeverPolls() {
        let recorder = PollRecorder()
        let coordinator = recorder.coordinator()
        coordinator.updateLyrics(.synced(Self.lyrics()))
        #expect(recorder.starts.isEmpty)
        coordinator.updateLyrics(.unavailable)
        coordinator.setDemand(UUID(), active: true)
        coordinator.updateLyrics(.plain(Lyrics(text: "plain", source: nil)))
        coordinator.updateLyrics(.synced(SyncedLyrics(lines: [], source: "test")))
        #expect(recorder.starts.isEmpty)
        #expect(recorder.stops == 0)
    }

    @Test func timingReplacementRestartsButTextChangesDoNot() {
        let recorder = PollRecorder()
        let coordinator = recorder.coordinator()
        coordinator.setDemand(UUID(), active: true)
        coordinator.updateLyrics(.synced(Self.lyrics()))
        coordinator.updateLyrics(.synced(Self.lyrics(text: "romanized")))
        #expect(recorder.starts.count == 1)
        coordinator.updateLyrics(.synced(Self.lyrics(start: 200)))
        #expect(recorder.starts.count == 2)
        #expect(recorder.resets == 2)
        #expect(recorder.starts.last == Self.lyrics(start: 200).bridgeLineRanges)
        coordinator.updateLyrics(.unavailable)
        #expect(recorder.stops == 1)
        #expect(recorder.resets == 3)
    }

    static func lyrics(start: Int = 0, text: String = "line") -> SyncedLyrics {
        SyncedLyrics(lines: [SyncedLyricLine(timeInMs: start, duration: 1000, text: text, words: nil)], source: "test")
    }
}

// MARK: - PollRecorder

@MainActor
private final class PollRecorder {
    var starts: [[[String: Int]]] = []
    var stops = 0
    var resets = 0

    func coordinator() -> LyricsDemandCoordinator {
        LyricsDemandCoordinator(
            start: { self.starts.append($0) },
            stop: { self.stops += 1 },
            resetDisplay: { self.resets += 1 }
        )
    }
}
