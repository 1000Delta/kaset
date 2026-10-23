import Foundation
import Testing

struct MenuBarLyricsLocalizationTests {
    @Test func newStringsShipChineseAndEnglishFallbacks() throws {
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Kaset/Resources")
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: resources.appendingPathComponent("Localizable.xcstrings")))
        let catalog = try #require((raw as? [String: Any])?["strings"] as? [String: Any])
        let keys = [
            "Show Lyrics in Menu Bar", "Maximum Menu Bar Width", "Menu Bar Lyrics",
            "Show the current synced lyric, or the track title when no line is available.",
            "Menu bar lyrics remain available when the main window is closed.",
            "Show lyrics and playback controls", "Current Lyric", "Next Lyric", "Open Main Window",
        ]
        let locales = try FileManager.default.contentsOfDirectory(at: resources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "lproj" }.map { $0.deletingPathExtension().lastPathComponent }
        for key in keys {
            let entry = catalog[key] as? [String: Any]
            let translations = entry?["localizations"] as? [String: Any]
            for locale in locales {
                let unit = (translations?[locale] as? [String: Any])?["stringUnit"] as? [String: Any]
                let value = unit?["value"] as? String
                #expect(value != nil, "Missing \(locale): \(key)")
                if locale.hasPrefix("zh-") {
                    #expect(value != key)
                } else {
                    #expect(value == key)
                }
            }
        }
    }
}
