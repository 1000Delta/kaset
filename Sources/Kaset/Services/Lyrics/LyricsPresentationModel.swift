import Foundation
import Observation

/// Application-owned lyric result and loading identity; independent of window/popover lifetimes.
@MainActor
@Observable
final class LyricsPresentationModel {
    private(set) var currentLyrics: LyricResult = .unavailable
    private(set) var isLoading = false
    private(set) var videoId: String?

    @ObservationIgnored private let polling: LyricsDemandCoordinator
    @ObservationIgnored private let load: @MainActor (LyricsSearchInfo, Bool) async -> LyricResult
    @ObservationIgnored private var demands: Set<UUID> = []
    @ObservationIgnored private var info: LyricsSearchInfo?
    @ObservationIgnored private var syncedEnabled = true
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var didLoad = false

    init(polling: LyricsDemandCoordinator, load: @escaping @MainActor (LyricsSearchInfo, Bool) async -> LyricResult) {
        self.polling = polling
        self.load = load
    }

    func setDemand(_ id: UUID, active: Bool) {
        if active {
            self.demands.insert(id)
        } else {
            self.demands.remove(id)
        }
        self.polling.setDemand(id, active: active)
        self.loadIfNeeded()
    }

    /// Pass nil for advertisements, regular YouTube video playback, or no current music item.
    func updateTrack(_ info: LyricsSearchInfo?, syncedEnabled: Bool) {
        guard self.videoId != info?.videoId || self.syncedEnabled != syncedEnabled else { return }
        self.generation += 1
        self.task?.cancel()
        self.task = nil
        self.info = info
        self.videoId = info?.videoId
        self.syncedEnabled = syncedEnabled
        self.didLoad = false
        self.isLoading = false
        self.currentLyrics = .unavailable
        self.polling.updateLyrics(.unavailable)
        self.loadIfNeeded()
    }

    /// Romanization can change text without replacing timing or starting another fetch.
    func refreshLyrics(_ result: LyricResult, videoId: String) {
        guard self.videoId == videoId, self.didLoad, !self.isLoading else { return }
        self.currentLyrics = result
        self.polling.updateLyrics(result)
    }

    private func loadIfNeeded() {
        guard !self.demands.isEmpty, !self.didLoad, self.task == nil, let info = self.info else { return }
        let requestGeneration = self.generation
        let syncedEnabled = self.syncedEnabled
        let load = self.load
        self.isLoading = true
        self.task = Task { [weak self] in
            let result = await load(info, syncedEnabled)
            guard let self, self.generation == requestGeneration else { return }
            self.currentLyrics = result
            self.isLoading = false
            self.didLoad = true
            self.task = nil
            self.polling.updateLyrics(result)
        }
    }
}
