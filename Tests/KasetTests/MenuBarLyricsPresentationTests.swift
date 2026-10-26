import Foundation
import Testing
@testable import Kaset

struct MenuBarLyricsPresentationTests {
    private let lyrics = SyncedLyrics(lines: [
        SyncedLyricLine(timeInMs: 1000, duration: 1000, text: "first\n line", words: nil),
        SyncedLyricLine(timeInMs: 3000, duration: 1000, text: "  ", words: nil),
        SyncedLyricLine(timeInMs: 4000, duration: 1000, text: "最后一句 🎵", words: nil),
    ], source: "test")

    @Test func currentAndNextUseLineBoundariesAndSingleLineText() {
        let value = MenuBarLyricsPresentation(title: "track", result: .synced(self.lyrics), lineIndex: 0, timeMs: 1500)
        #expect(value.current == "first line")
        #expect(value.next == "最后一句 🎵")
    }

    @Test(arguments: [0, 2500, 3500, 6000])
    func introInterludeBlankAndEndFallBackToTitle(time: Int) {
        let value = MenuBarLyricsPresentation(title: "track", result: .synced(self.lyrics), lineIndex: nil, timeMs: time)
        #expect(value.current == "track")
        if time == 0 {
            #expect(value.next == "first line")
        }
        if time == 2500 {
            #expect(value.next == "最后一句 🎵")
        }
        if time == 6000 {
            #expect(value.next == nil)
        }
    }

    @Test func unsyncedAndInvalidIndexFallBackWithoutLeakingPlainLyrics() {
        for result: LyricResult in [.unavailable, .plain(Lyrics(text: "not synced", source: nil)), .synced(self.lyrics)] {
            let value = MenuBarLyricsPresentation(title: "track", result: result, lineIndex: 99, timeMs: nil)
            #expect(value.current == "track")
        }
    }

    @Test func defaultIsOptInAndPersistedWidthIsClamped() throws {
        let name = "MenuBarLyricsPresentationTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(!MenuBarLyricsPreferences.loadEnabled(from: defaults))
        #expect(MenuBarLyricsPreferences.loadWidth(from: defaults) == 240)
        defaults.set(true, forKey: MenuBarLyricsPreferences.enabledKey)
        defaults.set(9999, forKey: MenuBarLyricsPreferences.widthKey)
        #expect(MenuBarLyricsPreferences.loadEnabled(from: defaults))
        #expect(MenuBarLyricsPreferences.loadWidth(from: defaults) == 480)
        defaults.set(-1, forKey: MenuBarLyricsPreferences.widthKey)
        #expect(MenuBarLyricsPreferences.loadWidth(from: defaults) == 120)
        #expect(MenuBarLyricsPreferences.clampWidth(.infinity) == 240)
        #expect(MenuBarLyricsPreferences.clampWidth(.nan) == 240)
    }
}
