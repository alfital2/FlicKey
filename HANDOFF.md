## Status

The opt-in imported-app rules feature and validated Firefox support are merged into `dev`. Auto-fix now detects and self-recovers when its global keyboard monitor cannot start because Accessibility has not yet been granted: it retries during startup until available, then stops polling, exposes a warning in General settings, and leaves categorical unavailable/recovered events in opted-in diagnostics. Build 53 is the current Release test artifact; Debug QA unlock and real Release licensing remain separated.

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
- Diagnosed auto-fix startup failure after live Accessibility grant: Firefox/manual AX recovered dynamically, but the global typing monitor had been created too early and was not retried.
- Added an idempotent monitor install, permission-aware startup retry/backoff, visible Settings warning, and privacy-safe unavailable/recovered diagnostic events. Retry stops permanently once the monitor starts.
- Added retry-policy and diagnostic-schema coverage. Full unit suite passes 502/502; build 53 awaits the final Release rebuild.

## Open questions / blockers

- Build 53 needs live approval of auto-fix recovery and the imported-app interaction.
- The build-51 DMG is Apple-Development signed for arm64 QA and intentionally not a notarized release artifact.

## Next steps

1. Validate auto-fix in build 53 after a normal launch with Accessibility already granted.
2. Validate the self-heal path on QA by granting Accessibility after launch and confirming no relaunch is needed.
3. Finish imported-app upgrade/interaction validation, then promote from `dev` only after approval.

_Last updated: 2026-09-10 by Codex_
