## Status

The user-approved reverted Firefox build-43 source remains the official baseline. The complete Firefox cold-start/tab-awareness fix is committed on `fix/firefox-cold-start-ax` through `d2e89db`, including the readiness, browser-chrome, stale-web-area, and notification-registration lifecycle corrections. The user repeatedly tested Firefox quit/relaunch and per-tab switching and reports that it now works. A Developer-ID-signed local Release build of this source is running as PID 42460 from `/private/tmp/flickey-firefox-dialog-fix.FpFk0p/Build/Products/Release/FlicKey.app`.

## Recent changes

- Fixed the remaining focus-cycle dependency at its lifecycle source: Gecko could accept `AXObserverCreate` during cold launch while rejecting individual notification registrations. FlicKey now retains successful registrations and retries only missing ones once the Firefox accessibility tree is proven readable.
- Clear Firefox's cached AX web-area object on tab-shaped mouse/keyboard input, preventing an old selected-page object from continuing to return a valid but stale URL.
- Preserved the earlier fixes that reject Firefox chrome dialogs as sites, avoid caching untrackable elements, prefer the outer page over nested iframe areas, and wait for Gecko accessibility readiness.
- Focused browser tests pass 42/42 and the full unit suite passes 494/494. The running app is 0.5.4 (43); complete nested `codesign --verify --deep --strict --all-architectures` verification passes.
- Relaunched the corrected app for testing, and the user manually repeated the original cold-start/tab-switch scenario successfully several times.

## Open questions / blockers

- No Firefox behavior blocker remains from the reported scenario. The current artifact is a local signed test build, not a newly numbered notarized release DMG.
- Merging into the official development line and producing a distributable artifact should happen only when the user explicitly requests the release step.

## Next steps

1. Treat `d2e89db` and its prerequisite Firefox commits as the validated implementation to merge into the official development line.
2. When requested, create a fresh uniquely numbered Developer-ID-signed/notarized artifact and verify the exact mounted DMG before publishing it.
3. Keep the abandoned arm64 signing experiment separate under `reverted/firefox-build44-arm64-signing-experiment`.

_Last updated: 2026-09-09 by Codex_
