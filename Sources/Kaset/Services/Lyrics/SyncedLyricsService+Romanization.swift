import Foundation
import Observation

extension SyncedLyricsService {
    convenience init(providers: [LyricsProvider] = [LRCLibProvider()]) {
        let romanization = RomanizationService()
        self.init(providers: providers) { synced in
            guard romanization.isEnabled else { return synced }
            let romanized = romanization.romanizeAll(synced)
            guard !romanized.isEmpty else { return synced }
            var lines = synced.lines
            for index in lines.indices {
                lines[index].romanizedText = romanized[lines[index].id]
            }
            return SyncedLyrics(lines: lines, source: synced.source)
        }
        self.observeRomanizationSetting()
    }

    private func observeRomanizationSetting() {
        withObservationTracking {
            _ = SettingsManager.shared.romanizationEnabled
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshCurrentRomanization()
                self?.observeRomanizationSetting()
            }
        }
    }
}
