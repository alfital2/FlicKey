## Status

`dev` is the official development line. It contains Firefox and other discovered-browser per-site memory, no hardcoded ordinary-app catalog, an opt-in “Import all my apps” control, and immediate per-app preference learning for imported/manually added ordinary apps. The recent auto-fix monitor-health experiment has been reverted.

## Recent changes

- Reverted the two auto-fix monitor-health commits because the requested dev scope is browser memory plus the redesigned app rules.
- Made an input-source change in an active listed ordinary app immediately become that app’s persisted preferred source, including while the Apps settings pane is already open.
- Captured app identity at notification time and suppressed FlicKey-generated layout notifications, preventing rapid app switches from learning a stale/programmatic source.
- Kept browsers and conversation apps out of app-wide learning so their per-site/per-conversation memory remains authoritative.
- Bumped the local dev build to 0.5.4 (54); the full 502-test unit suite passes.

## Open questions / blockers

- The local Apple Development signature has valid code structure but its certificate chain reports `CSSMERR_TP_NOT_TRUSTED` on strict verification. Build 54 is intended for local host testing, not distribution.

## Next steps

1. Manually verify: enable “Import all my apps,” focus an ordinary app showing “Not defined,” change the input source, and confirm its open settings row updates immediately.
2. Switch away and back to confirm the learned language is restored; separately smoke-test Firefox tab/site memory.
3. If approved, prepare a Developer ID signed/notarized distributable from `dev` with a new build number.

_Last updated: 2026-09-11 by Codex_
