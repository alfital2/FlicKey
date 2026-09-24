## Status

Local `dev` combines the multilingual converter (`7807319`) and global continuous-typing auto-fix (`c20623b`) through merge commit `910898d`. Its code is installed and running on the user's Mac as Developer-ID-signed FlicKey 0.5.6 build 74 at `/Applications/FlicKey.app`; exactly one process was verified and `autoSwitchEnabled` remained 1. Auto-fix remains opt-in/beta; this is a local QA installation, not a release or beta graduation. `main` and remote refs are unchanged.

## Recent changes

- Merged the continuous-typing input barrier and live auto-fix QA matrix with `dev`'s multilingual converter; kept both the Russian UI test entry point and the auto-fix test entry points when resolving test-runner conflicts.
- Verified the combined tree: 564 host unit tests passed with zero failures, 2/2 Russian conversion UI tests and 16/16 continuous auto-fix UI tests passed in the disposable `flickey-terminal-qa` Tart VM, and Release configuration compiled (ad-hoc local build only). The VM was stopped afterward.
- Built the exact merged `dev` code as local QA build 74, signed Sparkle and the app with the same Developer ID as build 73, verified deep signature/bundle/version/hash/no coverage instrumentation, saved build 73 at `build/HostQA/Previous/InstalledBuild73-active.app` (and `InstalledBuild73.app`), installed 74 at the same Applications path, and launched it.

## Open questions / blockers

- A user's 135-frame GIF at `/Users/tal/Library/Caches/poof/poof-1790262959645.gif` proves build 73 leaves the initial `a` when clean `akuo akuo ` becomes `aשלום שלום ` in Codex's text UI inside Terminal. The matching 18:15:58 FlicKey log recorded a `tailMutated` rewrite mismatch. Cause is not yet distinguished between a short AX span and a missed synthetic Backspace. The existing VM `vared` test did not cover this TUI; the user accepts this known issue for a beta merge, not for release.
- The broad VM UI sweep had macOS Accessibility/XCTest stalls and is not green. Mail, ChatGPT desktop, secure native fields, and other editors lack full qualification. Russian layouts with no functional spelling dictionary and IMEs remain limited.
- Build 74 has not been manually qualified on the host. Do not assume the known Codex-in-Terminal issue is confined to that text UI or fixed by the merge; it is the same auto-fix mechanism.

## Next steps

1. Investigate the confirmed Codex-in-Terminal deletion bug and add a real text-UI fixture; the existing `vared` test is insufficient.
2. Address the stalled broad UI harness and remaining app coverage before considering beta graduation or release.
3. Collect host feedback on build 74. Decide separately whether/when to publish local `dev`; do not infer release approval from this beta QA install.

_Last updated: 2026-09-24 by Codex_
