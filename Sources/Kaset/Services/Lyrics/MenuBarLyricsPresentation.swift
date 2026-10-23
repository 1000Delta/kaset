import Foundation

// MARK: - MenuBarLyricsPresentation

/// A line-boundary snapshot, not a playback timer. The full strings remain available to accessibility.
struct MenuBarLyricsPresentation {
    let current: String
    let next: String?

    init(title: String, result: LyricResult, lineIndex: Int?, timeMs: Int?) {
        guard case let .synced(lyrics) = result else {
            self.current = Self.singleLine(title)
            self.next = nil
            return
        }
        let validIndex = lineIndex.flatMap { lyrics.lines.indices.contains($0) ? $0 : nil }
        let text = validIndex.map { Self.singleLine(lyrics.lines[$0].text) } ?? ""
        self.current = text.isEmpty ? Self.singleLine(title) : text
        let candidates = lyrics.lines.enumerated().filter { index, line in
            if let validIndex {
                return index > validIndex
            }
            return line.timeInMs > (timeMs ?? -1)
        }
        self.next = candidates.lazy.map { Self.singleLine($0.element.text) }.first { !$0.isEmpty }
    }

    private static func singleLine(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

// MARK: - MenuBarLyricsPreferences

enum MenuBarLyricsPreferences {
    static let enabledKey = "settings.menuBarLyricsEnabled"
    static let widthKey = "settings.menuBarLyricsMaxWidth"
    static let widthRange = 120.0 ... 480.0
    static let defaultWidth = 240.0

    static func loadEnabled(from defaults: UserDefaults) -> Bool {
        defaults.object(forKey: self.enabledKey) as? Bool ?? false
    }

    static func loadWidth(from defaults: UserDefaults) -> Double {
        self.clampWidth(defaults.object(forKey: self.widthKey) as? Double ?? self.defaultWidth)
    }

    static func clampWidth(_ width: Double) -> Double {
        guard width.isFinite else { return self.defaultWidth }
        return min(max(width, self.widthRange.lowerBound), self.widthRange.upperBound)
    }
}
