## Status

Local `dev`'s app code remains at `1fa9d53`, combining multilingual conversion and opt-in continuous-typing auto-fix. FlicKey 0.5.6 build 74 remains the installed host QA app; this session tested fresh builds from `dev` in disposable Tart VMs without changing that installation. Host and Tart unit suites are green, but the live manual TextEdit suite is not, so multilingual UI qualification is incomplete. `main` and remote refs are unchanged.

## Recent changes

- Ran the full host suite on the fresh `dev` build: 564 tests, zero failures and skips. Result: `build/DevMultilingualQA-tests-20260924.xcresult`; log: `build/dev-multilingual-host-test.log` from the main workspace root.
- Ran the full suite in Tart: 564 tests, zero failures and skips after disabling an extra US layout in the disposable `flickey-ui` VM. The independent 16-layout, 4-sample Cartesian test passed, covering 960 directed conversions against macOS `UCKeyTranslate`.
- Live Tart checks on the exact app source: Russian TextEdit 2/2, Spotlight 2/2, and continuous typing 16/16 on `flickey-terminal-qa` passed. The first `flickey-ui` continuous run was 12/16 because all four Firefox fixture DOM snapshots were empty; those four passed on the other VM, so Firefox coverage remains sensitive to VM state.
- Manual TextEdit conversion was 3/5 on repeated runs across both VMs. The custom ⌃⌥9 chord left `akuo` unchanged, and selected-word conversion changed the surrounding `left`/`right` text. Diagnostic app/test edits did not resolve these failures and were restored; only this handoff changed. Both VMs were stopped. Tart result bundles and transcripts are under `build/dev-merge-worktree/build/tart/results`.

## Open questions / blockers

- Diagnose the two reproducible TextEdit failures before declaring manual multilingual conversion fully qualified. Selection was verified as exactly `akuo` before the trigger; the app logged an Accessibility conversion, then a later retry converted the whole phrase. The custom shortcut recorded in Settings but did not convert in TextEdit. Neither cause is established.
- The previously confirmed build 73 Codex-in-Terminal issue (`akuo akuo ` becoming `aשלום שלום `) remains unaddressed in build 74. The broad UI sweep previously stalled on Accessibility/XCTest; other editors, IMEs, and dictionary-limited layouts remain unqualified.
- Build 74 is a local QA install. No release, push, or beta graduation was authorized or done.

## Next steps

1. Reproduce and fix the selected-word and custom-chord TextEdit failures with focused live tests, then rerun the five-case manual conversion suite.
2. Investigate the Codex-in-Terminal deletion issue with a representative fixture and repeat focused continuous typing tests.
3. Stabilize Firefox and broad UI fixtures, then expand live coverage to additional native layouts and editors before release consideration.

_Last updated: 2026-09-24 by Codex_
