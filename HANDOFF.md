## Status

Firefox support is implemented on `feature/firefox-browser-support` (feature commit `6908437`). A test-quality audit added regression coverage and fixes; all 486 unit tests pass, including 34 browser tests. Signed UI reruns pass the Support suite (3/3) and the previously failing shortcut preset test. The two Firefox live UI tests currently launch without an Accessibility prompt but do not observe the seeded layout switch, so that boundary still needs investigation in a clean VM.

## Recent changes

- Replaced loose SDEF text matching with XML property parsing after a new regression test proved that documentation prose could misclassify a browser as AppleScript-capable.
- Normalized browser hosts to lowercase and removed a DNS root dot, with a regression test for `WWW.Example.COM.`.
- Expanded browser discovery coverage for background-only apps and case-insensitive duplicate bundle IDs, including preference for the installed Applications copy.
- Updated stale Settings UI labels and the Support UI test's intended 30-day trial contract; added a stable accessibility identifier for the state-dependent purchase button.
- Ran the full unit suite successfully. A signed UI run exposed stale assertions and external LNProbe modal interference; focused reruns confirmed the Support and shortcut Settings fixes.

## Open questions / blockers

- The Firefox XCUITests run under the Accessibility-authorized Developer ID identity but currently leave the input source on ABC. Determine whether launch timing, browser discovery timing, or the live AX reader is responsible; manual use had worked before this run.
- Two TextEdit hotkey UI tests lose the TextEdit `TextView` accessibility element after firing the shortcut. Their conversion assertion remains inconclusive and appears to be test-harness instability.
- LNProbe2 is running from `/Users/tal/Applications/LNProbe2.app` for another session and its local-network permission dialog can intercept UI automation on the host. Do not terminate it without coordinating that work.
- The VM must grant Accessibility access to its own signed FlicKey build and have Firefox plus ABC and Hebrew-PC input sources enabled for live tests.

## Next steps

1. In a clean macOS VM, clone the repo, check out `feature/firefox-browser-support`, and grant Accessibility access to the exact FlicKey test-build signing identity.
2. Reproduce `FirefoxBrowserIntegrationUITests` while collecting FlicKey logs to trace catalog discovery, AX URL reads, and routing callbacks.
3. Stabilize or replace the stale TextEdit element assertion, then rerun the signed default UI suite.
4. Rebuild and relaunch the Developer ID Release app after the audit commit is finalized.

_Last updated: 2026-09-07 by Codex_
