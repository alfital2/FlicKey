## Status

`feature/import-all-apps` is based directly on the validated Firefox `dev` branch. It replaces the abandoned automatic-learning experiment with an explicit import model: no ordinary apps are hardcoded, an optional checkbox lists installed ordinary apps as `Not defined`, and only an explicit language choice enables per-app enforcement. Firefox/Safari per-site and supported chat per-conversation behavior remain unchanged. Local QA build 49 is running with Settings open.

## Recent changes

- Removed the hardcoded ordinary-app catalog and its implicit English/Hebrew defaults.
- Added `Import all my apps`; while enabled, standard installed apps are discovered and shown without receiving a rule.
- Added the `Not defined` rule state, which routes to `leaveAsIs` and never changes the active input source.
- Persist an imported app's identity only after the user explicitly chooses a source, so that rule remains active even if import-all is later disabled.
- Kept discovered browsers on `Auto (per-site)` and conversation providers on `Auto (per-conversation)`, preserving the validated Firefox implementation from `dev`.
- Added coverage for import toggling, undefined routing, explicit-rule persistence, and settings persistence. Full unit suite passes 499/499.
- Built and relaunched arm64 Debug QA build 49 from `/private/tmp/flickey-import-all-b49.g2a7jd/Build/Products/Debug/FlicKey.app`.

## Open questions / blockers

- Build 49 needs the user's visual/behavioral approval, especially the checkbox wording and whether configured apps should remain listed after import-all is turned off.
- No build-49 DMG has been requested or packaged.

## Next steps

1. Validate the Apps pane: checkbox off, checkbox on, `Not defined`, explicit language switching, and checkbox off again.
2. Adjust the interaction if requested, then package a fresh QA artifact only when needed.
3. Merge to `dev` after approval.

_Last updated: 2026-09-10 by Codex_
