import Foundation

/// Owns the single WebView line-boundary subscription across independent lyric surfaces.
@MainActor
final class LyricsDemandCoordinator {
    private let start: ([[String: Int]]) -> Void
    private let stop: () -> Void
    private let resetDisplay: () -> Void

    init(start: @escaping ([[String: Int]]) -> Void, stop: @escaping () -> Void, resetDisplay: @escaping () -> Void) {
        self.start = start
        self.stop = stop
        self.resetDisplay = resetDisplay
    }

    private var demands: Set<UUID> = []
    private var ranges: [[String: Int]] = []
    private var activeRanges: [[String: Int]] = []

    func setDemand(_ id: UUID, active: Bool) {
        if active {
            self.demands.insert(id)
        } else {
            self.demands.remove(id)
        }
        self.reconcile()
    }

    func updateLyrics(_ result: LyricResult) {
        if case let .synced(lyrics) = result {
            self.ranges = lyrics.bridgeLineRanges
        } else {
            self.ranges = []
        }
        self.reconcile()
    }

    private func reconcile() {
        let desired = self.demands.isEmpty ? [] : self.ranges
        guard desired != self.activeRanges else { return }
        self.activeRanges = desired
        self.resetDisplay()
        if desired.isEmpty {
            self.stop()
        } else {
            self.start(desired)
        }
    }
}
