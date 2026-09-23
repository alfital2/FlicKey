## Status

`feat/multilingual-layouts` is a committed feature branch created directly from `main` at `4d1f6ff`, with its clean worktree at `build/multilingual-main-worktree`. It carries the multilingual conversion/manual-shortcut work without the newer continuous-typing auto-fix changes. All 559 host tests passed. Tart live TextEdit tests passed (five existing Hebrew/shortcut cases plus two new Russian cases). The Spotlight conversion test passed twice; a separate input-source typing-rig test failed once immediately after switching layouts and passed on rerun. Main and the user's running app remain unchanged. The root worktree remains on `fix/auto-fix-continuous-typing` with pre-existing uncommitted combined changes.

## Recent changes

- Created and committed the isolated multilingual branch from main so the feature is reviewable without continuous-typing edits.
- Added repeatable Tart Russian UI coverage for ABC → Russian → ABC and Russian physical typing → ABC; both live TextEdit tests passed twice with no skips.
- Ran the existing Tart TextEdit conversion suite: all five tests passed, including selected-text replacement and custom shortcut persistence.
- Ran the Spotlight suite twice. Search conversion passed both times; the typing-rig's first key briefly used the prior Latin layout on one run, then the whole suite passed on rerun. This is a real observed transition risk, not a conversion-engine failure proven by the test.
- Stopped the Tart VM after testing. VM reports and transcripts are under `build/tart/results` in the original root worktree.

## Open questions / blockers

- The Spotlight first-key transition needs investigation before claiming seamless immediate typing after an input-source switch.
- Live UI coverage now includes TextEdit and Spotlight but not Russian in browsers or other editors. Prior review also identified possible manual-edit risks around stale on-screen text and fixed monitor-resume timing.
- Some layouts lack functional macOS spell-check dictionaries; text-only reconstruction cannot resolve every lost physical-key distinction. IMEs remain outside the verified scope.

## Next steps

1. Investigate and stabilize the observed Spotlight layout-transition race; keep the failing transcript as evidence.
2. Expand live qualification to Russian in other common editors and browser fields, then rerun the relevant UI suites.
3. Review and merge the multilingual branch separately from continuous-typing work when ready.

_Last updated: 2026-09-24 by GPT-6 / Codex_
