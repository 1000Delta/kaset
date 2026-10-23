import Foundation

/// Production lyrics load path: synced providers first, then the plain-lyrics fallback.
///
/// Extracted from `ApplicationLyricsController` so the fallback and cancellation
/// sequence is exercised by behaviour tests instead of only by the app wiring.
@MainActor
struct ApplicationLyricsLoader {
    private let service: SyncedLyricsService
    private let fetchPlainLyrics: (String) async throws -> Lyrics

    init(service: SyncedLyricsService, fetchPlainLyrics: @escaping (String) async throws -> Lyrics) {
        self.service = service
        self.fetchPlainLyrics = fetchPlainLyrics
    }

    func load(_ info: LyricsSearchInfo, syncedEnabled: Bool) async -> LyricResult {
        guard !Task.isCancelled else { return .unavailable }

        if syncedEnabled {
            await self.service.fetchLyrics(for: info)
        }
        guard !Task.isCancelled else { return .unavailable }

        // Synced lyrics disabled, or no provider had a timed match.
        if case .unavailable = self.service.currentLyrics {
            do {
                let plain = try await self.fetchPlainLyrics(info.videoId)
                guard !Task.isCancelled else { return .unavailable }
                self.service.fallbackToPlainLyrics(plain, videoId: info.videoId)
            } catch {
                DiagnosticsLogger.api.error("Failed to load plain lyrics fallback: \(error.localizedDescription)")
            }
        }

        return self.service.currentLyrics
    }
}
