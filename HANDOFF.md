## Status

Local `dev` combines multilingual conversion and opt-in continuous-typing auto-fix. The entitlement audit identified and fixed Release test-mode bypass, paid-era trial recovery, running-app expiry, monitor shutdown, and license persistence/validation safeguards. Build 74 remains a QA install; the new local Release build is ad-hoc and unpublished. Project metadata is still 0.5.6/build 60, so this is not yet a releasable artifact. `main` and remote refs are unchanged.

## Recent changes

- Restricted `-uiTestReset` and other UI test behavior to Debug, so a customer Release process cannot restart into an isolated fresh trial. The compiled Release binary contains no test-reset or entitlement-simulation switch strings.
- Added a trial-state backup and recovery logic that preserves post-cutoff first-run time and elapsed ratchet when Keychain state is lost, while retaining the historical grandfathering fallback. Replaced delete-before-add Keychain writes, and made license activation fail visibly if persistence fails.
- Added a 60-second entitlement check, hourly trial ratchet persistence, a stop path for all paid feature monitors, periodic license revalidation, and a guard against an old validation response clearing a newly activated license. Successful Lemon Squeezy responses now require this store's ID.
- Host unit suite passed 569/569. Tart Support suite passed 5/5 live UI cases, including expired paywall and an expired TextEdit double-Shift that left wrong-layout text untouched. Final Release build succeeded; `git diff --check` and `bash -n scripts/tart.sh` passed. Disposable Tart VM was stopped.
- Earlier combined-tree QA remains: 564 host and 564 Tart unit tests, 960 directed conversions across 16 layouts, Russian TextEdit/Spotlight, and 30/30 Arabic PC TextEdit repetitions passed before these entitlement edits.

## Open questions / blockers

- Actual checkout, valid-key activation, refund/revocation, and upgrade migration from a shipped 0.5.6 install have not been exercised end to end. An old post-cutoff install with both its Keychain stamp and new backup absent remains indistinguishable from a grandfathered legacy install; the compatibility fallback grants it free access. This ambiguity needs an explicit policy decision before broad rollout.
- Published GitHub latest is v0.5.6, and the project/appcast still declare 0.5.6/build 60; choose a higher version and build above QA build 74 before packaging. The final DMG/ZIP has not been Developer ID signed, notarized, or published.
- Earlier UI limits remain: custom shortcut physical-key behavior, Codex-in-Terminal stray-character rewrite, Firefox VM variability, and Arabic auto-correction without a functional Arabic dictionary.

## Next steps

1. Decide the legacy missing-stamp policy and test a real valid license plus revocation in a disposable environment.
2. Run an upgrade test from published 0.5.6, then complete the remaining release-quality UI checks.
3. Bump version/build, sign and notarize an exact candidate, verify Sparkle and install/upgrade paths, roll out to a small cohort, then publish broadly after review.

_Last updated: 2026-09-25 by Codex_
