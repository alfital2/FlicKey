## Status

`feature/import-all-apps` is based directly on the validated Firefox `dev` branch. It replaces the abandoned automatic-learning experiment with an explicit import model: no ordinary apps are hardcoded, an optional checkbox lists installed ordinary apps as `Not defined`, and only an explicit language choice enables per-app enforcement. Existing users' explicitly saved ordinary-app choices are migrated, while untouched legacy defaults disappear. Firefox/Safari per-site and supported chat per-conversation behavior remain unchanged. Debug QA artifacts now unlock automatically on every Mac; Release entitlement behavior is unchanged. QA build 51 is the current artifact.

## Recent changes

- Removed the hardcoded ordinary-app catalog and its implicit English/Hebrew defaults.
- Added `Import all my apps`; while enabled, standard installed apps are discovered and shown without receiving a rule.
- Added the `Not defined` rule state, which routes to `leaveAsIs` and never changes the active input source.
- Persist an imported app's identity only after the user explicitly chooses a source, so that rule remains active even if import-all is later disabled.
- Added upgrade migration for explicit legacy rules whose app identity was previously supplied only by the hardcoded catalog; untouched hardcoded defaults are deliberately not restored.
- Kept discovered browsers on `Auto (per-site)` and conversation providers on `Auto (per-conversation)`, preserving the validated Firefox implementation from `dev`.
- Added coverage for import toggling, undefined routing, explicit-rule persistence, settings persistence, and legacy-rule migration. Full unit suite passes 500/500.
- Made normal Debug QA builds resolve as licensed without a key, while preserving the real isolated trial path for UI tests and all explicit entitlement simulation flags. Release builds do not compile this bypass.
- Labeled Debug settings as `QA TEST BUILD — Unlocked` so testers can identify the artifact directly.
- Built arm64 Debug QA build 51. Its exact mounted DMG passes `hdiutil verify` and strict nested signature verification.

## Open questions / blockers

- Build 51 needs the user's visual/behavioral approval, especially the checkbox wording and upgrade behavior.
- The build-51 DMG is Apple-Development signed for arm64 QA and intentionally not a notarized release artifact.

## Next steps

1. Validate the Apps pane: checkbox off, checkbox on, `Not defined`, explicit language switching, and checkbox off again.
2. Confirm on a clean QA Mac that build 51 opens unlocked without arguments or a license key.
3. Confirm an existing explicitly configured app remains listed and enforced after update.
4. Adjust if requested, then merge to `dev` after approval.

_Last updated: 2026-09-10 by Codex_
