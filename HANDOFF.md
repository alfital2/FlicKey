## Status

`feat/multilingual-layouts` is a committed feature branch created directly from `main` at `4d1f6ff`, with its clean worktree at `build/multilingual-main-worktree`. It carries the multilingual conversion/manual-shortcut work without the newer continuous-typing auto-fix changes. All 559 host tests passed. Tart live TextEdit tests passed (five existing Hebrew/shortcut cases and two new Russian cases). The Spotlight conversion test passed twice. The separate Spotlight typing-rig test failed once in an earlier run, passed on rerun, and then passed 50 of 50 sequential repetitions with a fresh test runner each time. Main and the user's running app remain unchanged. The root worktree remains on `fix/auto-fix-continuous-typing` with pre-existing uncommitted combined changes.

## Recent changes

- Repeated only `SpotlightTypingRigUITests.testSpotlightAcceptsLatinThenClearsThenAcceptsHebrew` 50 times in the Tart VM with test-runner relaunch between attempts to measure the previously observed failure.
- All 50 runs passed with zero failures or skips. The saved Xcode result confirms 50 repetitions; the per-run log shows mean 3.535 seconds, median 3.494 seconds, and range 3.253–4.687 seconds.
- Saved the result at `build/multilingual-main-worktree/build/tart/results/SpotlightRig50-20260924.xcresult` and the raw log at `build/multilingual-main-worktree/build/spotlight-rig-50.log`; stopped the Tart VM afterward.

## Open questions / blockers

- The earlier single Spotlight first-key transition failure remains unexplained. A clean 50-run batch lowers concern but does not prove the race impossible or establish its frequency across other machines.
- Live UI coverage includes TextEdit and Spotlight but not Russian in browsers or other editors. Prior review also identified possible manual-edit risks around stale on-screen text and fixed monitor-resume timing.
- Some layouts lack functional macOS spell-check dictionaries; text-only reconstruction cannot resolve every lost physical-key distinction. IMEs remain outside the verified scope.

## Next steps

1. Investigate the earlier Spotlight first-key transition if it recurs, retaining both the failing transcript and the clean 50-run report.
2. Expand live qualification to Russian in other common editors and browser fields, then rerun the relevant UI suites.
3. Review and merge the multilingual branch separately from continuous-typing work when ready.

_Last updated: 2026-09-24 by GPT-6 / Codex_
