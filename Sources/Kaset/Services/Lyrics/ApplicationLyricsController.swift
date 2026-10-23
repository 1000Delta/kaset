import Foundation
import Observation

// MARK: - LyricsPlaybackInput

/// Narrow snapshot seam: no UI, network, timer, or playback-service abstraction.
struct LyricsPlaybackInput {
    let track: LyricsSearchInfo?
    let syncedEnabled: Bool
    let menuBarEnabled: Bool

    init(track: LyricsSearchInfo?, isShowingAd: Bool, isMusicSource: Bool, syncedEnabled: Bool, menuBarEnabled: Bool) {
        self.track = isShowingAd || !isMusicSource ? nil : track
        self.syncedEnabled = syncedEnabled
        self.menuBarEnabled = menuBarEnabled
    }
}

// MARK: - ApplicationLyricsController

/// Launch-owned observation; lyrics keep working with every music window and sidebar closed.
@MainActor
final class ApplicationLyricsController {
    let model: LyricsPresentationModel
    private let service: SyncedLyricsService
    private let input: @MainActor () -> LyricsPlaybackInput
    private let menuDemand = UUID()
    private var observedVideoId: String?
    private var observedSyncedEnabled: Bool?

    init(service: SyncedLyricsService, input: @escaping @MainActor () -> LyricsPlaybackInput, polling: LyricsDemandCoordinator, load: @escaping @MainActor (LyricsSearchInfo, Bool) async -> LyricResult) {
        self.service = service
        self.input = input
        self.model = LyricsPresentationModel(polling: polling, load: load)
        self.observeInputs()
        self.observeService()
    }

    private func observeInputs() {
        let input = withObservationTracking {
            self.input()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeInputs() }
        }
        // Do not track mutations: observing model/service internals here would create a feedback loop.
        if self.observedVideoId != input.track?.videoId || self.observedSyncedEnabled != input.syncedEnabled {
            self.observedVideoId = input.track?.videoId
            self.observedSyncedEnabled = input.syncedEnabled
            self.service.clearLyrics(for: input.track?.videoId)
        }
        self.model.updateTrack(input.track, syncedEnabled: input.syncedEnabled)
        self.model.setDemand(self.menuDemand, active: input.menuBarEnabled)
    }

    private func observeService() {
        let snapshot = withObservationTracking {
            (self.service.currentLyrics, self.service.currentVideoId)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeService() }
        }
        if let videoId = snapshot.1 {
            self.model.refreshLyrics(snapshot.0, videoId: videoId)
        }
    }
}
