import Foundation
import Testing

/// Source ownership guards complement the behavioral coordinator tests without launching any UI.
struct LyricsIntegrationTests {
    @Test func lyricViewsOnlyLeaseSharedDemand() throws {
        for path in ["Sources/Kaset/Views/LyricsView.swift", "Sources/Kaset/Views/LegacyFallbackViews.swift"] {
            let source = try Self.source(path)
            #expect(source.contains("@Environment(LyricsPresentationModel.self)"))
            #expect(source.contains("setDemand(self.lyricsDemandID, active: true)"))
            #expect(source.contains("setDemand(self.lyricsDemandID, active: false)"))
            for forbidden in ["startLyricsPoll", "stopLyricsPoll", "fetchLyrics(for:", "getLyrics(videoId:"] {
                #expect(!source.contains(forbidden), "\(path) must not own \(forbidden)")
            }
        }
    }

    @Test func launchOwnsObservationAndBothWindowsReceiveSameModel() throws {
        let app = try Self.source("Sources/Kaset/KasetApp.swift")
        let initializer = app.components(separatedBy: "    var body: some Scene")[0]
        #expect(initializer.contains("AppLyricsWiring("))
        let wiring = try Self.source("Sources/Kaset/AppLyricsWiring.swift")
        #expect(wiring.contains("ApplicationLyricsController("))
        #expect(wiring.contains("MenuBarLyricsController("))
        #expect(app.contains(".environment(self.lyrics.controller.model)"))
        #expect(app.contains("lyricsModel: self.lyrics.controller.model"))
        let mini = try Self.source("Sources/Kaset/MiniPlayerWindowController.swift")
        #expect(mini.contains(".environment(lyricsModel)"))
        let menu = try Self.source("Sources/Kaset/Views/MenuBarLyricsController.swift")
        for forbidden in ["Timer", "TimelineView", "onAppear", "Task.sleep", "startLyricsPoll", "stopLyricsPoll"] {
            #expect(!menu.contains(forbidden))
        }
        #expect(menu.contains(".byTruncatingTail"))
        #expect(menu.contains("button.toolTip = presentation.current"))
        #expect(menu.contains("setAccessibilityValue(presentation.current)"))
    }

    @Test func architectureDecisionIsRegistered() throws {
        let adr = try Self.source("docs/adr/0042-menu-bar-lyrics-shared-demand.md")
        let registry = try Self.source("docs/adr/README.md")
        #expect(adr.contains("LyricsDemandCoordinator"))
        #expect(adr.contains("LyricsPresentationModel"))
        #expect(registry.contains("0042-menu-bar-lyrics-shared-demand.md"))
    }

    private static func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
