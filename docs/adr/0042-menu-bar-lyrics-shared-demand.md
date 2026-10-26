# ADR-0042: Application-owned menu bar lyrics and shared demand

## Status

Proposed (fork implementation; pending full Xcode build and human UI validation)

## Context

The sidebar and mini-player lyrics views independently fetched lyrics and started/stopped the same WebView poll. Closing one surface could stop another surface's subscription. A persistent menu bar label cannot depend on the main window, sidebar, or popover appearing to fetch and observe music playback. The existing synced-lyrics WebView bridge already publishes line-boundary changes; adding a native playback timer would duplicate work.

## Decision

- Construct `ApplicationLyricsController` during `KasetApp.init`, retain it for the application lifetime, and inject its single `LyricsPresentationModel` into the main and mini-player windows. Application-owned Observation tracks current music identity, advertisements, the playback arbiter, and settings even when windows are closed.
- `LyricsPresentationModel` owns one load per track/synced-setting generation. Independent UUID demand leases represent the menu bar and each visible lyrics view. Repeated acquire/release operations are idempotent. A result may finish after the last release (avoiding close/reopen fetch storms), a surface that opens after a failed load may retry once, and successful results stay cached per track; no polling continues without demand. Track nil, advertisements, video playback, and synced-setting changes invalidate pending completions and clear displayed lyrics immediately.
- `LyricsDemandCoordinator` alone decides whether to start/stop the shared `SingletonPlayerWebView` line-boundary poll. It only polls nonempty synced timing with at least one lease. Timing replacement resets the displayed bucket; text-only/romanization changes do not restart polling. Views cannot directly stop another consumer's poll.
- Keep provider ranking, cache, and romanization in `SyncedLyricsService`. Coalesce simultaneous same-track searches and clear generation/loading state explicitly. The application loader shares the plain-lyrics fallback, checking cancellation after every suspension. A small display-transform seam permits real Foundation-only service tests without global preferences or network providers.
- Use a native `NSStatusItem` and transient `NSPopover` hosting a SwiftUI view, available on macOS 15.4 and 26. This gives an explicitly bounded status-item width and native tail truncation, tooltip, and accessibility value containing the complete single-line text. There is no label-side timer or popover-appearance bootstrap. The popover displays current/next lyrics, title/artist/album, music transport controls, and the existing main-window reveal action. Music controls are disabled while regular YouTube video owns playback.
- The feature is opt-in/default-off. Persist maximum width in points, clamped to 120–480 (default 240). No current synced line—including intro, gap, blank, plain-only, or unavailable lyrics—falls back to the track title. Ads and video never reuse music lyrics. With no music or video item loaded, the status item collapses to a music-note glyph whose tooltip and accessibility value use the localized “No Song Playing” string instead of reserving text width.
- Add English, Simplified Chinese, and Traditional Chinese strings to the catalog and every checked-in `.lproj` mirror together; the remaining locales explicitly fall back to English for new keys.

## Consequences

The native label and every lyrics panel share loading and polling without ownership collisions. Fetch acceptance and polling behavior are unit-testable through closures rather than a general playback/plugin abstraction. Existing controls and playback bridge behavior remain in their established services.

A status item can still be hidden by macOS when menu-bar space is exhausted. The configured value is a maximum, not reserved space. Human validation is required for notch/crowded-menu behavior, native truncation, VoiceOver, appearance, popover interaction, window reopening, and playback with all windows closed on macOS 15.4 and 26. No UI tests or app launch are authorized by this ADR.

The development host has Swift 6.1 command-line tools, while the real package requires Swift tools 6.2 and macOS 26 SDK APIs. Isolated tests compile actual Foundation-only production sources and repository Swift Testing files in a scratch package; they do not establish that the complete app builds or runs. Full-package non-UI tests and build must pass with Xcode 26 before publishing the fork.
