## Status

Firefox, Zen, ungoogled-chromium, and other discovered browser support is implemented on `feature/firefox-browser-support`. The production build and all 483 unit tests pass, the UI test target compiles, and live URL reads succeeded in Firefox, Zen, and ungoogled-chromium. Full Firefox UI automation still needs Accessibility access granted specifically to the Apple Development-signed debug build.

## Recent changes

- Replaced the hardcoded browser list with a cached LaunchServices catalog keyed by bundle ID, while filtering helper apps and cached browser copies found during live discovery.
- Added a bounded, cached Accessibility URL reader for Gecko. It activates Firefox's native accessibility tree before searching and preserves the prior tab when no reliable URL is available.
- Routed AppleScript browsers by bundle ID and retained existing per-app preferences and custom-app compatibility.
- Added catalog, routing, reader, and Firefox UI coverage; documented Gecko requirements; bumped the project to 0.5.4 build 36.
- Updated the original design plan with the activation and discovery findings from Firefox 155, Zen 1.22b, and ungoogled-chromium 152.

## Open questions / blockers

- The installed Developer ID release's Accessibility grant does not apply to the Apple Development-signed DerivedData build, which has a different designated requirement. Grant the debug build separately before expecting the live XCUITest suite to pass.
- Manual checks remain for Zen split-view focus, private browsing, Gecko with `accessibility.force_disabled=1`, and rapid tab switching.
- Unusual third-party HTTPS handlers may still appear if they are foreground apps outside known cache locations; the current filter removes all noise observed on this machine.

## Next steps

1. Grant Accessibility access to the DerivedData debug FlicKey build and run `scripts/test.sh browser-ui-firefox`.
2. Complete manual cases C12-C22 in `QA_TEST_PLAN.md`.
3. Review the feature commit, then open a pull request and respond to GitHub issue #1.

_Last updated: 2026-09-07 by Codex_
