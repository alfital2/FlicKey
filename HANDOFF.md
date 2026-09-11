## Status

`dev` is the official development line. It contains Firefox and other discovered-browser per-site memory, no hardcoded ordinary-app catalog, “Import all my apps,” and the optional “Remember language for apps I use” behavior. Accessibility-dependent features now monitor trust at startup and meaningful lifecycle events—without a timer—and pause or recover automatically when permission changes.

## Recent changes

- Added event-driven Accessibility trust checks on startup, app activation, wake, and session activation because macOS exposes a trust query but no permission-change notification.
- Auto-fix, hotkeys, and focus watching now stop safely when Accessibility is revoked and restart automatically after trust returns.
- Added an actionable Accessibility warning to the menu and an auto-fix status plus Settings button to General settings.
- Track global keyboard-monitor creation failures separately and retry on the next lifecycle event rather than polling.
- Bumped the local dev build to 0.5.4 (56); the full 511-test unit suite passes.

## Open questions / blockers

- The local Apple Development signing identity is suitable for host testing but not a Developer ID/notarized distribution artifact.

## Next steps

1. Revoke Accessibility, switch applications, and confirm the warning appears and auto-fix pauses.
2. Restore Accessibility, switch back to FlicKey or another app, and confirm auto-fix recovers without relaunching; test with `akuo vnmc `.
3. Repeat the permission and auto-fix checks in the UTM QA VM.

_Last updated: 2026-09-12 by Codex_
