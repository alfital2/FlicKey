## Status

`fix/auto-fix-global-retry` remains isolated from `main` and other worktrees. This session expanded the release-gate matrix and fixed a reproduced one-character Firefox layout-handoff race. Final focused results in the dedicated `flickey-terminal-qa` VM: 32/32 live auto-fix matrix passes (16 cases × 2), 10/10 extra Firefox two-tab race trials, 535 unit tests with 0 failures (8 environment skips), manual conversion 3/3, Spotlight 2/2, app switching 2/2, and undo/learned-block 1/1. The production Release configuration builds. The dedicated VM is stopped; host QA build 72 is unchanged and predates this fix. Do not promote from beta yet.

## Recent changes

- Added real-key Safari/Firefox two-tab isolation, Hebrew-PC→English, Russian amid multiple enabled layouts, 5 ms/key TextEdit/Terminal stress, valid-English no-conversion, and Safari/Firefox password-field non-mutation. Exact destination text/DOM and source are asserted, with focused Tart runners and repeat-count support.
- The new Firefox tab fixture reproduced `אנh` in otherwise-correct Hebrew. Protected replay now maps held keys to the target layout and holds them for a 60 ms TIS-to-app handoff. The focused 10/10 Firefox trials and final 32/32 combined matrix passed after this fix.
- Corrected test-only assumptions: reverse-direction accepts either enabled English layout (`US`/`ABC`); the Caps Lock lookup assertion matches the host/VM ABC table; app-switching fixtures disable normal first-visit auto-remember. This isolates genuine no-rule preservation without changing normal production behavior.

## Open questions / blockers

- The broad default UI sweep is not green: it had a stale unforced-app fixture (now corrected and passing alone), an undo test invalidated by a 61-second XCTest AX query stall (passing alone), then Safari AX snapshot calls timed out repeatedly for >5 minutes. It was gracefully stopped; a fresh-VM focused matrix did not reproduce the AX stalls. The broad sweep has not been rerun to completion.
- These are finite offline fixtures, not universal macOS proof. Apple Mail, ChatGPT desktop, Chrome, secure native fields, and many third-party editors remain untested on this version. The 60 ms handoff may warrant a subjective latency check. Host QA build 72 does not include this session's fix and previously showed an Accessibility Access Required alert.
- Host Apple Mail and ChatGPT app remain outside this VM matrix unless available as disposable, privacy-safe fixtures; the installed host build 72 still had an Accessibility Access Required alert at last check.

## Next steps

1. Review the branch changes and this QA evidence; rerun the broad UI sweep only after addressing the VM AX timeout/harness issue, not by waiving failures.
2. If a new signed host QA build is desired, build and install from this branch only with appropriate approval, verify Accessibility trust, then test Apple Mail/ChatGPT and subjective handoff latency with the user. Build 72 is stale.
3. Keep the feature opt-in/beta until the remaining app and harness coverage is acceptable; merge/promote only after that decision.

_Last updated: 2026-09-24 by Codex_
