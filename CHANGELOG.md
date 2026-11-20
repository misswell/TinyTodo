# Changelog

All notable changes to TinyTodo are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/).

## [1.3.1] — 2026-11-20

### Fixed

- Panel content now hangs off a single 14pt rail. Before, each band carried its own number:
  day labels sat at 8pt (hugging the window edge), the header / quick input / tab bar at 14pt,
  and the todo rows at 26pt, because a plain-style macOS `List` adds its own 8pt leading margin
  and `.contentMargins(.horizontal, 0)` does not cancel it. Rows, group labels, header, input
  and history all line up now; measured on screen at 2x, every band starts at 14.0–15.0pt.
- The day-group label no longer draws a full-bleed hairline under it. A plain `List` renders
  that separator for every `Section` header and none of `.listSectionSeparator(.hidden)` /
  `.listRowSeparator(.hidden, edges: .all)` remove it; the label is now a row, which renders
  clean and stays inside its own group for dragging.
- Removed the 4pt step between a history day label and the rows under it: the row's own
  horizontal padding is cancelled so both share one edge.

### Changed

- Panel metrics moved into `TinyTodo/Support/PanelLayout.swift` (`contentInset`, `glyphWidth`,
  `glyphTextGap`, the measured `List` margins and the derived row insets) instead of repeating
  14/18/12 in each view. `PanelLayoutTests` guards the derived values.
- Row density is unchanged at a 32pt pitch; only the columns moved.
- Notarization for 1.3.1: app `3ea7c440-…` and DMG `39412a1b-…` Accepted; DMG SHA-256 `6dbf2ddc…`.

## [1.3.0] — 2026-11-19

Milestone: TinyTodo now ships a Mac app and an iOS app from one codebase.

### Added

- iOS app (`TinyTodoIOS`, iOS 17+) in the same Xcode project and repository: day-grouped pending
  list, one-line capture, history search, swipe to restore/delete, settings with iCloud Drive folder
  selection (security-scoped bookmark) and local fallback.
- `Shared/` holds the model, GRDB database, repository, day grouping and JSON backup codec compiled
  into both apps, so the two platforms share one schema and one file format.
- macOS build and CI now compile the shared sources; CI gained an `ios-build` job.

### Changed

- macOS 1.3.0 (build 10); iOS 1.0.0 (build 1).
- Notarization for 1.3.0: app `46199d48-…`, DMG `b40b45b4-…` Accepted; DMG SHA-256 `d242ccc2…`.

## [1.2.4] — 2026-11-19

### Added

- Pending todos are grouped by the day they were created (今天 / 昨天 / earlier dates), matching the
  history page's rhythm. Dragging still reorders inside a day; the other days keep their place.
- iOS app target (`TinyTodoIOS`): pending list with day groups, one-line capture, history search,
  swipe actions, and the same SQLite schema; the data layer is now shared by both apps under
  `Shared/`.
- iOS reaches the Mac's iCloud Drive folder through a security-scoped bookmark, chosen once in
  Settings › 同步, with a local fallback and a reload when iCloud replaces the file underneath.
- JSON backup format moved to `Shared/Services/BackupCodec.swift` so both platforms read/write the
  same file.

### Changed

- 130 unit/integration tests (pending day grouping, reordering within a section).
- iOS has no separate test target on purpose: the data layer is the same `Shared/` source covered by
  the macOS suite, and the simulator test runner hangs on this machine
  ("test runner hung before establishing connection") after several resets, so the target was removed
  rather than shipped broken.
- macOS version 1.2.4 (build 9); iOS 1.0.0 (build 1).
- Notarization for 1.2.4: DMG `22708995-…` Accepted; DMG SHA-256 `da46b358…`.

## [1.2.3] — 2026-11-18

### Fixed

- The 1.2.2 DMG shipped a **1.2.1** binary: `project.yml` was bumped without running
  `xcodegen generate`, so the old `MARKETING_VERSION` stayed in the project file and the update
  client refused the asset. Fixed at the root:
  `scripts/release.sh` now regenerates the project itself and aborts when the built bundle's
  `CFBundleShortVersionString` differs from `project.yml`.
- `UpdateInstaller.verifyBundle` reports a version mismatch as `versionMismatch` (with a hint about
  the release build) instead of the misleading "not a valid TinyTodo.app".

### Added

- Quick-input draft persistence: whatever is half-typed is written to `UserDefaults` on every
  change and restored on launch, so hiding the panel, quitting, or a crash never loses it. It is
  cleared only when the todo is actually submitted.
- The quick-input field wraps and grows up to 4 lines (then scrolls); the panel extends downward by
  the same amount so the tab bar stays visible, and the `+` icon stays beside the first line.

### Changed

- 127 unit/integration tests (bundle verification, draft persistence, field growth/cap).
- Notarization for 1.2.3: app `4011e48b-…` and DMG `0bc8a66a-…` Accepted; DMG SHA-256 `f818b9c3…`.

## [1.2.2] — 2026-11-18

### Fixed

- Quick-input placeholder no longer sits below the typed text. The placeholder is now drawn by the
  same `NSTextView` as the input, so both share one font (13 pt), one `textContainerInset` and one
  baseline; measured on screen: plus icon centre y=810.0, placeholder centre y=810.5 (2× pixels).
- The single line is centred by `VerticalTextLayout.insetY(containerHeight:lineHeight:)` instead of
  a hardcoded 4 pt inset, so a taller/shorter field stays centred.

### Changed

- 117 unit/integration tests (vertical centring, shared text origin across states).
- Notarization for 1.2.2: app `38eafa7d-…` and DMG `397792a2-…` Accepted; DMG SHA-256 `e1083efa…`.

## [1.2.1] — 2026-11-17

### Changed

- Panel spacing/margins: 38 pt header with the progress centred independently of the pin/gear
  buttons, 14 pt side margins everywhere, roomier rows (5 pt vertical padding, 7 pt hover corner),
  wider quick-input bar, larger tab bar and history rhythm.
- Menu bar badge: shows the number of **remaining** todos (verified in a live run: 2 pending →
  badge `2`, 1 completed → unchanged). 1.1.0 and earlier showed today's completions.

### Notes

- Version 1.2.1 (build 6). Install once manually only if you are still on 1.0.x; 1.1.0+ can update
  from Settings › 更新.
- Notarization: app `6e3d9b94-…` and DMG `f6ce46b5-…` Accepted; DMG SHA-256 `6a445e58…`.

## [1.2.0] — 2026-11-17

### Added

- iCloud Drive storage (Settings › 数据 › 使用 iCloud Drive…): pick a folder in iCloud Drive and the
  SQLite database lives there as a single file (`journal_mode=DELETE`, `synchronous=FULL`), so
  iCloud replicates it to other Macs. Switching copies data with a conflict choice, keeps a local
  backup when switching back, and asks to restart.
- Menu bar badge now shows the number of unfinished todos (instead of today's completions);
  the menu still lists both remaining and today's completed counts. Toggle in Settings.

### Changed

- 111 unit/integration tests (storage location/migration, iCloud journal mode, badge text).
- Version 1.2.0 (build 5).

## [1.1.0] — 2026-11-17

### Added

- In-app online updates (Settings › 更新, menu bar › 检查更新…): checks
  `releases/latest` on GitHub, compares semantic versions, downloads the DMG and verifies
  SHA-256 digest from the release, bundle id/version, Developer ID team `U8U443D7ZL`,
  designated requirement (so TCC grants survive) and Gatekeeper/notarization before installing.
- Self-replacement helper (`Resources/update-helper.sh`): waits for the app to quit, swaps the
  verified bundle in `/Applications` with a backup, strips quarantine and relaunches.
  Copies outside `/Applications` are refused with a manual-download message.
- Automatic check once per launch (toggleable), silent on failure; manual check and download
  progress live in Settings.

### Changed

- Menu bar left click expands the panel as the app's own dropdown anchored under the status item
  (Magpie-style), and dismisses on outside click; the floating panel via `⌥⇧T` keeps its saved
  position and always-on-top behaviour.
- 100 unit/integration tests (version comparison, release decoding, digest, service/installer
  gating, menu placement).
- 1.1.0 app submission `1564f6f0-…`, DMG submission `6a787ad4-…` (Accepted), DMG SHA-256
  `2a08b7f1…`; notarized and stapled.
- Version 1.1.0 (build 4).

## [1.0.1] — 2026-11-17

### Changed

- Menu bar icon: left click now expands/hides the todo panel so work can start immediately;
  right click (or Control-click) opens the menu (today count, quick add, history, settings, quit).
- 82 unit/integration tests (added menu-bar click routing tests).

## [1.0.0] — 2026-11-17

### Added

- Native floating `NSPanel` (AppKit), always-on-top by default, visible across Spaces and
  auxiliary to full-screen apps, draggable/resizable, remembers its frame per display.
- Menu bar extra with today's completed count, show/hide, quick add, history, settings, quit.
- Global hotkey `⌥⇧T` via Carbon `RegisterEventHotKey` (no Accessibility permission), editable
  in Settings with conflict detection (`KeyboardShortcuts`).
- One-field quick capture: type + Enter creates a todo; paste multi-line text to create many;
  Pinyin/IME composition never submits a half-typed todo.
- Complete with one click; completed items leave the pending list and land in history with
  `completed_at`. Undo (`⌘Z` and toast button) restores complete / delete / reorder / rename.
- History page grouped by local day (今天 / 昨天 / 7 天 / 30 天), month picker, full-text search,
  per-day counts, restore to todo, delete record, cumulative total.
- Local SQLite storage (GRDB) in WAL mode at
  `~/Library/Application Support/TinyTodo/TinyTodo.sqlite`, versioned migrations (v1 → v3),
  crash-safe, no automatic history cleanup.
- JSON export/import with ISO-8601 timestamps; import merges by id and never clears data.
- Settings window: appearance (system/light/dark), panel opacity, always-on-top, Spaces,
  menu bar count, launch at login (`SMAppService`), hotkeys, database path/version/size,
  reset window position.
- App icon (light/dark friendly) and adaptive light/dark UI.
- 79 unit + integration tests covering repository, migrations, import/export, grouping,
  undo, view-model flows, window geometry and real panel behavior.
- XCUITest target for launch/create/complete/history/settings flows.
- GitHub Actions workflow: build, test, DMG packaging.
- `scripts/release.sh` builds a Developer ID signed Release (Hardened Runtime + secure
  timestamp, `get-task-allow` stripped); `scripts/notarize.sh` notarizes and staples both the
  app and the DMG with the machine's verified `agentspace-notary` profile.
- `scripts/make_dmg.sh` produces an ad-hoc developer DMG; `scripts/generate_icon.py` rebuilds
  the icon set.
- 1.0.0 shipping DMG: Developer ID `U8U443D7ZL`, notarized (submissions
  `dea98b04-2bf2-4a36-91d0-9fb2de1514f6`, `b0751ebc-fae2-4a7c-af18-d3dd09125e81`), stapled,
  Gatekeeper accepted.

### Notes

- Local-only by design: no accounts, no network, no iCloud in 1.0.0.
- Reminders, subtasks, tags/projects and AI features are intentionally out of scope for v1.
