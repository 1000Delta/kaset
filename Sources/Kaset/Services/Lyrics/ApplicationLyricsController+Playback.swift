import Foundation

extension ApplicationLyricsController {
    convenience init(player: PlayerService, arbiter: PlaybackArbiter, service: SyncedLyricsService, client: any YTMusicClientProtocol, settings: SettingsManager) {
        let polling = LyricsDemandCoordinator(
            start: { SingletonPlayerWebView.shared.startLyricsPoll(lineRanges: $0) },
            stop: { SingletonPlayerWebView.shared.stopLyricsPoll() },
            resetDisplay: {
                player.currentLyricsLineIndex = nil
                player.currentLyricsDisplayTimeMs = nil
            }
        )
        self.init(service: service, input: {
            let info = player.currentTrack.map {
                LyricsSearchInfo(title: $0.title, artist: $0.artistsDisplay, album: $0.album?.title, duration: $0.duration, videoId: $0.videoId)
            }
            return LyricsPlaybackInput(
                track: info, isShowingAd: player.isShowingAd, isMusicSource: arbiter.activeSource == .music,
                syncedEnabled: settings.syncedLyricsEnabled, menuBarEnabled: settings.menuBarLyricsEnabled
            )
        }, polling: polling) { info, syncedEnabled in
            guard !Task.isCancelled else { return .unavailable }
            if syncedEnabled {
                await service.fetchLyrics(for: info)
            }
            guard !Task.isCancelled else { return .unavailable }
            if case .unavailable = service.currentLyrics {
                do {
                    let plain = try await client.getLyrics(videoId: info.videoId)
                    guard !Task.isCancelled else { return .unavailable }
                    service.fallbackToPlainLyrics(plain, videoId: info.videoId)
                } catch {
                    DiagnosticsLogger.api.error("Failed to load plain lyrics fallback: \(error.localizedDescription)")
                }
            }
            return service.currentLyrics
        }
    }
}
