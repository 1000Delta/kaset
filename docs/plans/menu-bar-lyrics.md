# Menu Bar Lyrics Implementation Plan

> **For Hermes:** Use subagent-driven-development to implement and review this plan.

**Goal:** Add opt-in, single-line macOS menu bar lyrics that keep working with the main window or lyrics sidebar closed.

**Architecture:** Use an application-owned lyrics presentation controller and a small shared demand/polling coordinator. Sidebar, mini-player and menu bar consume the same lyrics state and polling lifecycle. The menu bar is a thin native presentation surface; no duplicate providers, independent timers, external bridge or notch implementation.

**Tech Stack:** Swift 6, SwiftUI/AppKit, Observation, existing YTMusic/LRCLib providers, Swift Testing; no added dependencies.

## Constraints and verified environment

- Work only in `1000Delta/kaset`, branch `feat/menu-bar-lyrics`; no issues, PRs or comments to other repositories.
- Preserve unrelated changes and existing keyboard shortcuts; never run UI tests without explicit permission.
- Local host is macOS 15.5 with Swift 6.1 command-line tools; package requires Swift tools 6.2. A real `swift build` currently fails at the manifest-version prerequisite. Use a separate temporary Foundation-only Swift 6.1 harness for isolated domain tests and fork CI with Xcode 26 for complete build/unit/package verification. Do not lower the repository's tools version or claim local full-app verification.
- Preserve both Tahoe and Sequoia UI paths. Update localization catalog and checked-in strings together.

## Task 1 — Shared lyric demand and polling (TDD)

Create `Sources/Kaset/Services/Lyrics/LyricsDemandCoordinator.swift` (or equivalently named minimal coordinator), plus Swift Testing coverage in `Tests/KasetTests/LyricsDemandCoordinatorTests.swift`. Inject polling start/stop closures so lifecycle logic can run without WebKit. Cover two consumers, idempotent demand, release-one versus release-last, empty/plain/unavailable results, track/timing replacement, and disabling lyrics. Write and run failing behavior tests before implementation, then run passing tests. Keep the coordinator Foundation/Observation-only so exactly the production source and tests can also execute in a temporary package on this host.

## Task 2 — Application-owned loading and presentation (TDD)

Create `Sources/Kaset/Services/Lyrics/LyricsPresentationController.swift` or equivalent. Own lifecycle outside the main window: observe current music track, lyric result and opt-in settings; consolidate loading for active consumers; discard stale completions after track changes or cancellation. Ensure closing one surface cannot cancel another's demand, and that fetching/line polling stops with no consumers. Reuse `SyncedLyricsService`, `PlayerService`, YTMusicClient and the existing line-boundary bridge.

Tests must cover single-flight requests for simultaneous consumers, A-to-B stale completions, clearing current track, preference toggling, and text fallback before first line, between lines or for unavailable/plain lyrics. Use dependency seams or pure snapshots for tests rather than source-string assertions.

## Task 3 — Menu bar, existing views and settings integration

- Create a dedicated menu bar label/popover presentation under `Sources/Kaset/Views/`.
- Wire at app scope in `Sources/Kaset/KasetApp.swift`; ensure demand is not tied to popover appearance or main-window `.task`.
- Opt-in setting defaults off; configurable bounded text width with sensible default. Render one line with truncation, tooltip/accessibility containing full text. Label should observe line changes, not continuously read playback progress.
- Popover shows current lyric, next lyric, track metadata, previous/play-pause/next, and open-main-window action. Retain readable fallback on no song/unsynced results and pause; hide stale lyrics during advertisements or YouTube-video playback.
- Integrate both `LyricsView.swift` and legacy `LegacyFallbackViews.swift` and mini-player environment wiring with shared demand. Avoid direct independent `stopLyricsPoll` calls owned by views.
- Add controls in `MusicSettingsView.swift`, persisted keys/defaults in `SettingsManager.swift` and matching settings tests.
- Update `Resources/Localizable.xcstrings` first, then all corresponding `.lproj/Localizable.strings` mirrors (English fallback permitted for untranslated locales, provide Simplified/Traditional Chinese for new strings).

## Task 4 — Verification and architecture note

Add a new ADR under `docs/adr/` and register it. Explain ownership, demand lifecycle, fallback rules, cancellation/stale state handling, and manual acceptance checks. Parent handles `.github/workflows/` so do not modify workflow files in implementation tasks.

Run formatting/lint if tools exist, focused and complete unit tests and full build/package in fork CI. Do not auto-run UI tests. Review specification first, then code quality; fix accepted issues and rerun affected tests/review. Document actual results and remaining manual UI/playback limitations honestly.

## Task 5 — Fork-only publication

Commit coherent reviewed changes, push only to `origin` (the user's fork), and open a review PR with `--repo 1000Delta/kaset --base main --head feat/menu-bar-lyrics`. Verify exact repository, head SHA, base repository and CI checks after publication. Never merge without a new instruction, never publish to another repository, and never install or launch a development app on the user's desktop without permission.
