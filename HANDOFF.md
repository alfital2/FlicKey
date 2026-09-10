## Status

The opt-in imported-app rules feature is merged into `dev` at `f0c5349`, alongside the validated Firefox support. No ordinary apps are hardcoded: users can import installed apps as `Not defined`, and only an explicit language choice enables per-app enforcement. Existing explicit rules migrate while untouched legacy defaults disappear. Debug QA builds unlock automatically, but Release builds retain real licensing. A signed universal Release build 51 from merged `dev` is currently running locally.

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
- Merged `feature/import-all-apps` into `dev` after all 500 unit tests passed.
- Built a universal Release configuration from merged `dev`, verified it contains no QA-unlock marker, verified its complete nested signature, and launched it with no arguments from `dist/dev-release-b51/FlicKey-0.5.4-build51-dev-release-universal.app`.

## Open questions / blockers

- The merged build needs the user's final visual/behavioral approval, especially the checkbox wording and upgrade behavior.
- The build-51 DMG is Apple-Development signed for arm64 QA and intentionally not a notarized release artifact.

## Next steps

1. Validate the Apps pane in the running Release build: checkbox off/on, `Not defined`, explicit switching, and off again.
2. Confirm on a clean QA Mac that the separate Debug build 51 opens unlocked without arguments or a license key.
3. Confirm an existing explicitly configured app remains listed and enforced after update.
4. Promote from `dev` only after final approval.

_Last updated: 2026-09-10 by Codex_
