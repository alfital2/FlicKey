## Status

`dev` is the official development line. It contains Firefox and other discovered-browser per-site memory, no hardcoded ordinary-app catalog, “Import all my apps,” and an optional “Remember language for apps I use” mode. Listed ordinary apps learn manual input changes immediately; the optional mode also adds previously unseen apps and initializes their preference on first visit. The recent auto-fix monitor-health experiment remains reverted.

## Recent changes

- Added the opt-in “Remember language for apps I use” checkbox to the Apps tab.
- When enabled, first visiting an ordinary unlisted app adds it and stores the currently selected input source; later manual source changes update it.
- Preserved saved preferences on return instead of replacing them with the prior app’s source, and kept browser/chat memory out of app-wide learning.
- Bumped the local dev build to 0.5.4 (55); the full 508-test unit suite passes.

## Open questions / blockers

- The local Apple Development signing identity is suitable for host testing but not a Developer ID/notarized distribution artifact.

## Next steps

1. Manually verify: enable “Remember language for apps I use,” visit an unlisted ordinary app, and confirm it appears with the active language.
2. Change that app’s language, switch away/back, and confirm the newest preference is restored; separately smoke-test Firefox tab/site memory.
3. If approved, prepare a Developer ID signed/notarized distributable from `dev` with a new build number.

_Last updated: 2026-09-11 by Codex_
