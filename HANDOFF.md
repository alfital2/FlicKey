## Status

The user-approved reverted Firefox build-43 source remains the official baseline. The complete Firefox cold-start recovery is now on `fix/firefox-cold-start-ax`: initial AX readiness commit `b5a3b82`, followed by root-cause fix `417cbbf`. A Developer-ID-signed local Release build of the current source is running as PID 41201 from `/private/tmp/flickey-firefox-dialog-fix.FpFk0p/Build/Products/Release/FlicKey.app` for user validation.

## Recent changes

- Reproduced the focus-cycle dependency and proved Firefox's default-browser startup prompt replaces the page AX tree with `chrome://global/content/commonDialog.xhtml`; FlicKey had misclassified `global` as a website.
- Restricted per-site classification to HTTP(S) pages plus the existing explicit new-tab URLs, so browser chrome cannot become a memory key.
- Stopped caching readable-but-untrackable AX elements. Gecko can keep a dismissed prompt element alive with its old URL, which previously made the stale state permanent until leaving Firefox cleared the cache.
- Changed web-area selection to prefer the outermost focused/page area over nested iframe/widget areas. This prevents Firefox Home's embedded remote-content web area from winning while the outer page temporarily reports 0x0.
- Added focused-element AX hints so dismissing an in-window browser prompt triggers a prompt re-read, and expanded the Gecko probe with window/tree/watch diagnostics.
- Added regression coverage for internal Firefox URLs, stale-cache eligibility, and nested web-area ranking. Focused browser tests pass 42/42; the full unit suite passes 494/494.
- Verified the exact signed build live: Firefox remained active, the startup prompt was dismissed through AX, the real `about:home` tab appeared in 45 ms, and FlicKey applied its remembered new-tab layout without any focus cycle.

## Open questions / blockers

- The user should manually confirm normal tab switching and a Firefox quit/relaunch with the running build.
- This is a local Developer-ID-signed test build, not a notarized distributable. A newly numbered DMG should be produced only after user approval; earlier build-43 DMGs must not be reused.

## Next steps

1. Have the user test the running build, including Firefox quit/relaunch and tabs with different remembered layouts.
2. If approved, merge `417cbbf` (and its prerequisite `b5a3b82`) into the official development line.
3. Create a fresh uniquely numbered signed/notarized artifact and verify the exact mounted DMG before publishing it for VM validation.

_Last updated: 2026-09-09 by Codex_
