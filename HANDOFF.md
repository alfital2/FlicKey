## Status

`fix/forced-layout-handoff` is an isolated branch/worktree based on `dev` (`a700397`) and includes the existing `fix/app-memory-echo` commit (`1e98ccc`) unchanged. The forced-app handoff correction is committed at `fa99795`. Its Developer ID signed local QA build 0.6.0/77 is installed and running from `/Applications/FlicKey.app` on the user's Mac for manual testing. Build number 77 was overridden on the Xcode command line; `project.yml` still says 75. No merge, push, customer release, or `main` change occurred.

## Recent changes

- `AppWatcher` tracks a forced activation for 0.9 seconds. Notifications and checks at 0.15/0.4/0.75 seconds reapply the rule only while the same app is frontmost, using the shared programmatic-switch ledger.
- Tart results: 20 iterations of both main Terminal cases passed (40/40 tests, 240 alternating Russian/Hebrew visits and 20 relaunches); customer-memory suite passed 2 unit and 4 UI tests, including 40 Safari tab switches; app-switching suite passed 5/5. Full unit suite passed 575/575 in the VM's original ABC/Hebrew PC setup. The VM was restored and stopped.
- An initial full-unit run with Russian PC also enabled had six older `LayoutConverterTests` failures because those tests assume a two-layout cycle; no production handoff failure was found.
- Built Release target without coverage instrumentation, re-signed Sparkle and the app with Developer ID team `58XL8H22S9`, verified the bundle and same designated requirement as build 76, backed up build 76 at `build/FlicKey-76-installed.app` and `build/FlicKey-76-backup.app`, gracefully quit it, installed build 77, and verified its running process.

## Open questions / blockers

- User manual QA of build 77 is in progress. The branch is not merged into `dev`; the dev worktree retains an earlier uncommitted provisional guard and QA edits, so reconcile carefully. Live messenger switching still needs a logged-in app for end-to-end coverage.
- Release gates outside this fix remain notarized Sparkle update verification and broader host feedback.

## Next steps

1. Collect user feedback from build 77 on Terminal, WhatsApp, and browser switching; if needed, use the build 76 backup to revert.
2. Review and merge `fix/forced-layout-handoff` into `dev` after reconciling the dev worktree's provisional edits.
3. Continue release checks, and improve the older two-layout converter test fixture separately.

_Last updated: 2026-09-26 by Codex_
