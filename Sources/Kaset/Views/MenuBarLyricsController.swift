import AppKit
import Observation
import SwiftUI

// MARK: - MenuBarLyricsController

/// Native status item: explicit bounded geometry, a full-text tooltip, and no label-side timer.
@MainActor
final class MenuBarLyricsController: NSObject, NSPopoverDelegate {
    private let model: LyricsPresentationModel
    private let player: PlayerService
    private let arbiter: PlaybackArbiter
    private let youtubePlayer: YouTubePlayerService
    private let settings: SettingsManager
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var launchObserver: NSObjectProtocol?
    var openMainWindow: (() -> Void)?

    /// Horizontal room AppKit reserves around a status-item title (measured at ~15 pt per side).
    private static let titlePadding: CGFloat = 30

    init(model: LyricsPresentationModel, player: PlayerService, arbiter: PlaybackArbiter, youtubePlayer: YouTubePlayerService, settings: SettingsManager) {
        self.model = model
        self.player = player
        self.arbiter = arbiter
        self.youtubePlayer = youtubePlayer
        self.settings = settings
        super.init()
        self.popover.behavior = .transient
        self.popover.delegate = self
        // The app constructs this during `KasetApp.init`, which can run before
        // AppKit finishes launching. A status item created that early is unreliable.
        if NSApp?.isRunning == true {
            self.observeLabel()
        } else {
            self.launchObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didFinishLaunchingNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.observeLabel() }
            }
        }
    }

    var trackTitle: String {
        if self.arbiter.activeSource == .video {
            return self.youtubePlayer.currentVideo?.title ?? String(localized: "No Song Playing")
        }
        return self.player.currentTrack?.title ?? String(localized: "No Song Playing")
    }

    var artist: String {
        self.arbiter.activeSource == .music ? (self.player.currentTrack?.artistsDisplay ?? "") : ""
    }

    var album: String {
        self.arbiter.activeSource == .music ? (self.player.currentTrack?.album?.title ?? "") : ""
    }

    var presentation: MenuBarLyricsPresentation {
        let allowsLyrics = self.arbiter.activeSource == .music
            && !self.player.isShowingAd
            && self.model.videoId == self.player.currentTrack?.videoId
        return MenuBarLyricsPresentation(
            title: self.trackTitle,
            result: allowsLyrics ? self.model.currentLyrics : .unavailable,
            lineIndex: self.player.currentLyricsLineIndex,
            timeMs: self.player.currentLyricsDisplayTimeMs
        )
    }

    var canControlMusic: Bool {
        self.arbiter.activeSource == .music && self.player.currentTrack != nil
    }

    /// A video or music item is loaded, so the menu bar can show meaningful text.
    var hasPlayableItem: Bool {
        self.arbiter.activeSource == .video ? self.youtubePlayer.currentVideo != nil : self.player.currentTrack != nil
    }

    var isPlaying: Bool {
        self.player.isPlaying
    }

    func previous() {
        Task { await self.player.previous() }
    }

    func playPause() {
        Task { await self.player.playPause() }
    }

    func next() {
        Task { await self.player.next() }
    }

    func revealMainWindow() {
        self.popover.performClose(nil)
        self.openMainWindow?()
    }

    private func observeLabel() {
        let snapshot = withObservationTracking {
            // Include language so native tooltip/accessibility strings refresh without reopening.
            _ = self.settings.contentLanguage
            return LabelSnapshot(
                enabled: self.settings.menuBarLyricsEnabled,
                maxWidth: self.settings.menuBarLyricsMaxWidth,
                hasPlayableItem: self.hasPlayableItem,
                presentation: self.presentation
            )
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeLabel() }
        }
        self.updateStatusItem(
            enabled: snapshot.enabled,
            maxWidth: snapshot.maxWidth,
            hasPlayableItem: snapshot.hasPlayableItem,
            presentation: snapshot.presentation
        )
    }

    private struct LabelSnapshot {
        let enabled: Bool
        let maxWidth: Double
        let hasPlayableItem: Bool
        let presentation: MenuBarLyricsPresentation
    }

    private func updateStatusItem(
        enabled: Bool,
        maxWidth: Double,
        hasPlayableItem: Bool,
        presentation: MenuBarLyricsPresentation
    ) {
        guard enabled else {
            self.popover.performClose(nil)
            if let statusItem = self.statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
            }
            self.statusItem = nil
            return
        }
        if self.statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.target = self
            item.button?.action = #selector(self.togglePopover)
            self.statusItem = item
        }
        guard let item = self.statusItem, let button = item.button else { return }

        // Idle: a compact glyph instead of a permanent "No Song Playing" label.
        guard hasPlayableItem else {
            button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: String(localized: "Menu Bar Lyrics"))
            button.imagePosition = .imageOnly
            button.title = ""
            item.length = NSStatusItem.squareLength
            let idle = String(localized: "No Song Playing")
            button.toolTip = idle
            button.setAccessibilityLabel(String(localized: "Menu Bar Lyrics"))
            button.setAccessibilityValue(idle)
            button.setAccessibilityHelp(String(localized: "Show lyrics and playback controls"))
            return
        }

        let font = NSFont.menuBarFont(ofSize: 0)
        // Restore title rendering: the idle branch switched the cell to image-only,
        // and a nil image with `.imageOnly` leaves the title with an empty rect.
        button.imagePosition = .noImage
        button.image = nil
        button.font = font
        button.title = presentation.current
        button.cell?.usesSingleLineMode = true
        button.cell?.lineBreakMode = .byTruncatingTail
        let textWidth = (presentation.current as NSString).size(withAttributes: [.font: font]).width
        let naturalWidth = textWidth + Self.titlePadding
        item.length = min(CGFloat(MenuBarLyricsPreferences.clampWidth(maxWidth)), max(24, ceil(naturalWidth)))
        button.toolTip = presentation.current
        button.setAccessibilityLabel(String(localized: "Menu Bar Lyrics"))
        button.setAccessibilityValue(presentation.current)
        button.setAccessibilityHelp(String(localized: "Show lyrics and playback controls"))
    }

    /// Breaks the popover → hosting controller → view → controller reference loop.
    nonisolated func popoverDidClose(_: Notification) {
        Task { @MainActor [weak self] in
            self?.popover.contentViewController = nil
        }
    }

    @objc private func togglePopover() {
        if self.popover.isShown {
            self.popover.performClose(nil)
            return
        }
        guard let button = self.statusItem?.button else { return }
        self.popover.contentViewController = NSHostingController(
            rootView: MenuBarLyricsPopover(controller: self)
                .environment(\.locale, self.settings.contentLanguage.locale)
        )
        self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}

// MARK: - MenuBarLyricsPopover

private struct MenuBarLyricsPopover: View {
    let controller: MenuBarLyricsController

    var body: some View {
        let presentation = self.controller.presentation
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(self.controller.trackTitle)
                    .font(.headline)
                    .textSelection(.enabled)
                if !self.controller.artist.isEmpty {
                    Text(self.controller.artist).font(.subheadline).foregroundStyle(.secondary)
                }
                if !self.controller.album.isEmpty {
                    Text(self.controller.album).font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            if presentation.current != self.controller.trackTitle {
                Text(presentation.current)
                    .font(.body.weight(.medium))
                    .textSelection(.enabled)
                    .accessibilityLabel(String(localized: "Current Lyric"))
                    .accessibilityValue(presentation.current)
            }
            if let next = presentation.next {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Next Lyric")).font(.caption).foregroundStyle(.secondary)
                    Text(next).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            HStack(spacing: 22) {
                self.control(String(localized: "Previous Track"), symbol: "backward.end.fill", action: self.controller.previous)
                self.control(
                    self.controller.isPlaying ? String(localized: "Pause") : String(localized: "Play"),
                    symbol: self.controller.isPlaying ? "pause.fill" : "play.fill",
                    action: self.controller.playPause
                )
                self.control(String(localized: "Next Track"), symbol: "forward.end.fill", action: self.controller.next)
            }
            .buttonStyle(.plain)
            .disabled(!self.controller.canControlMusic)
            .frame(maxWidth: .infinity)
            Divider()
            Button(String(localized: "Open Main Window"), action: self.controller.revealMainWindow)
                .frame(maxWidth: .infinity)
        }
        .padding(18)
        .frame(width: 330)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func control(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 28, height: 28) }
            .help(title)
            .accessibilityLabel(title)
    }
}
