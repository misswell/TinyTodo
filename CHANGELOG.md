# Changelog

All notable changes to TinyTodo are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/).

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
- `scripts/make_dmg.sh` to produce an installable DMG; `scripts/generate_icon.py` to rebuild
  the icon set.

### Notes

- Local-only by design: no accounts, no network, no iCloud in 1.0.0.
- Reminders, subtasks, tags/projects and AI features are intentionally out of scope for v1.
