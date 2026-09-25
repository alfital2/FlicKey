## Status

Local `dev` contains the multilingual converter and opt-in continuous-typing auto-fix; the app source is unchanged from the build 74 QA install. This session added live Arabic PC regression coverage and ran it in the disposable `flickey-ui` Tart VM. All 30 repeated Arabic UI executions passed, and the VM was stopped. `main` and remote refs remain unchanged.

## Recent changes

- Added `ArabicConversionUITests` and the `scripts/tart.sh arabic-ui` entry point because prior Arabic coverage was unit-level only. The tests exercise `sghl` ↔ `سلام`, physical Arabic PC `b-a-d` → `لاشي` → `bad`, and separate `g+h` → `لا` → `gh` in TextEdit. Each case restores the VM's keyboard sources.
- Ran all three cases once, then ten iterations of each: 30/30 executions passed with zero failures or skips. Saved transcript: `build/tart/results/test-transcript-20260925-121332.txt`; result bundle: `build/tart/results/FlicKeyUITests-20260925-121332.xcresult` (paths relative to this worktree). `bash -n` and `git diff --check` passed.
- Prior fresh-`dev` QA remains: 564 host and 564 Tart unit tests passed with no skips, including a 960-case 16-layout conversion oracle; Russian TextEdit 2/2, Spotlight 2/2, and continuous typing 16/16 passed on the second Tart VM. The user indicated whole-line conversion in the selected-text case is expected, so that older UI assertion needs alignment.

## Open questions / blockers

- Arabic PC **manual** conversion is now live-tested in TextEdit. Automatic Arabic correction was not qualified: the audited host's Arabic spell-check dictionary probe failed, and automatic detection depends on functional dictionaries. Other Arabic keyboard variants, IMEs, and editors were not live-tested.
- The recorded ⌃⌥9 shortcut did not convert under synthetic Tart key delivery; physical-key behavior is unverified. Four Firefox fixtures failed with empty DOM snapshots on one VM and passed on another. The previously confirmed Codex-in-Terminal stray-character rewrite remains unaddressed in build 74.
- Build 74 is a local QA install. No release, push, or beta graduation occurred.

## Next steps

1. If broader Arabic support is needed, test additional Arabic keyboard variants and editors; qualify automatic correction only with a working Arabic dictionary.
2. Align the selected-text UI assertion with intended behavior and check the custom shortcut using physical keys.
3. Investigate the Codex-in-Terminal rewrite and stabilize the Firefox/broad UI fixtures before release consideration.

_Last updated: 2026-09-25 by Codex_
