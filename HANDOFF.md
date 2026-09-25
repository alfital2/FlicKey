## Status

`fix/forced-layout-handoff` is an isolated branch/worktree based on `dev` (`a700397`) and includes the existing `fix/app-memory-echo` commit (`1e98ccc`) unchanged. It adds a bounded correction for a late previous-app input-source selection that could override a forced Terminal English rule. The code is tested in the disposable Tart VM only; local QA build 76 from the separate echo branch remains installed on the user's Mac. No merge, push, customer release, or `main` change occurred.

## Recent changes

- `AppWatcher` tracks a forced activation for 0.9 seconds. Input-source notifications and checks at 0.15/0.4/0.75 seconds reapply the rule only while the same app remains frontmost. Reapplications use the shared programmatic-switch ledger so other apps do not learn them.
- Added live Terminal pinned-English coverage for Russian PC/Hebrew PC visits and relaunch, a deterministic late Russian selection, and leaving Terminal for unforced TextEdit. Added a three-site Safari layout test and focused Tart runner actions from the dev QA worktree.
- Tart results: 20 iterations of both main Terminal cases passed (40/40 tests, 240 alternating visits and 20 relaunches); customer-memory suite passed 2 unit and 4 UI tests, including 40 Safari tab switches; existing app-switching suite passed 5/5. Full unit suite passed 575/575 after restoring the VM's original ABC/Hebrew PC setup.
- An initial full-unit run with Russian PC also enabled had six `LayoutConverterTests` failures because those older tests assume a two-layout cycle; this is a test-fixture limitation, not a new handoff failure. Restored the VM to ABC/Hebrew PC and stopped it.

## Open questions / blockers

- The new branch has not been installed on the user's Mac or merged into `dev`; host QA and integration are pending. The older converter test fixtures should eventually state or enforce their two-layout precondition when a third language is enabled.
- Release gates outside this fix remain notarized Sparkle update verification and broader host feedback.

## Next steps

1. Review/merge `fix/forced-layout-handoff` into `dev` after the other session's echo branch work is reconciled.
2. Validate a local host build with Terminal, WhatsApp, and browser switching, then continue release checks.
3. Improve the older two-layout converter test fixture separately so a three-layout VM run reports the intended coverage cleanly.

_Last updated: 2026-09-26 by Codex_
