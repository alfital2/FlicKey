## Status

Local `dev` combines the multilingual converter (`7807319`) and global continuous-typing auto-fix (`c20623b`) through the isolated integration merge. Auto-fix remains opt-in/beta; this is not a release or beta graduation. The user's installed FlicKey build 73 is still the pre-merge auto-fix branch, not this combined code. `main` and remote refs are unchanged.

## Recent changes

- Merged the continuous-typing input barrier and live auto-fix QA matrix with `dev`'s multilingual converter; kept both the Russian UI test entry point and the auto-fix test entry points when resolving test-runner conflicts.
- Verified the combined tree: 564 host unit tests passed with zero failures, 2/2 Russian conversion UI tests and 16/16 continuous auto-fix UI tests passed in the disposable `flickey-terminal-qa` Tart VM, and Release configuration compiled (ad-hoc local build only). The VM was stopped afterward.

## Open questions / blockers

- A user's 135-frame GIF at `/Users/tal/Library/Caches/poof/poof-1790262959645.gif` proves build 73 leaves the initial `a` when clean `akuo akuo ` becomes `aשלום שלום ` in Codex's text UI inside Terminal. The matching 18:15:58 FlicKey log recorded a `tailMutated` rewrite mismatch. Cause is not yet distinguished between a short AX span and a missed synthetic Backspace. The existing VM `vared` test did not cover this TUI; the user accepts this known issue for a beta merge, not for release.
- The broad VM UI sweep had macOS Accessibility/XCTest stalls and is not green. Mail, ChatGPT desktop, secure native fields, and other editors lack full qualification. Russian layouts with no functional spelling dictionary and IMEs remain limited.

## Next steps

1. Investigate the confirmed Codex-in-Terminal deletion bug and add a real text-UI fixture; the existing `vared` test is insufficient.
2. Address the stalled broad UI harness and remaining app coverage before considering beta graduation or release.
3. Review the local `dev` merge and decide separately whether/when to publish it; do not infer release approval from this beta merge.

_Last updated: 2026-09-24 by Codex_
