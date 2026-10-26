import Foundation

/// App-lifetime lyric stack: one shared presentation model plus the menu bar surface.
///
/// Built during `KasetApp.init` so lyric observation and polling never depend on a
/// window, sidebar, or popover appearing.
@MainActor
struct AppLyricsWiring {
    let controller: ApplicationLyricsController
    let menuBar: MenuBarLyricsController

    init(
        player: PlayerService,
        arbiter: PlaybackArbiter,
        client: any YTMusicClientProtocol,
        youtubePlayer: YouTubePlayerService,
        settings: SettingsManager
    ) {
        let service = SyncedLyricsService(providers: [
            YTMusicSyncedProvider(client: client),
            LRCLibProvider(),
        ])
        let controller = ApplicationLyricsController(
            player: player,
            arbiter: arbiter,
            service: service,
            client: client,
            settings: settings
        )
        self.controller = controller
        self.menuBar = MenuBarLyricsController(
            model: controller.model,
            player: player,
            arbiter: arbiter,
            youtubePlayer: youtubePlayer,
            settings: settings
        )
    }
}
