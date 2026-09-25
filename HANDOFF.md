## Status

Local `dev` combines multilingual conversion and opt-in continuous-typing auto-fix with entitlement hardening. The user chose the generous legacy policy: surviving old preferences with no readable trial stamps qualify for free-forever grandfathering. Build 74 remains a QA install; no customer release, push, or change to `main` occurred. Project metadata is still 0.5.6/build 60, so the locally signed candidate is not a releasable update.

## Recent changes

- Recorded the user's Option A decision beside `TrialRecovery.choose`: protect early customers even though a rare post-cutoff install that loses both trial records can receive the same free access. The existing recovery test covers this behavior.
- Downloaded public v0.5.6 `FlicKey.zip` and built a locally Developer ID signed Release candidate with the same bundle ID and signing team. In a disposable Tart VM, a prior-preference case was grandfathered by 0.5.6 and stayed grandfathered in the candidate, matching Option A.
- Cleared only FlicKey state in that VM and repeated as a fresh post-cutoff customer: public 0.5.6 created a trial, the candidate preserved its first-run stamp (age 57 seconds, max elapsed 16), and after deleting the trial Keychain item the candidate retained the same stamp and restored the Keychain record. Temporary app copies were removed and the VM was stopped.
- Prior entitlement verification remains: 569/569 host unit tests; 5/5 Tart Support UI cases including expired paywall and no TextEdit conversion; Release compilation without test-reset switches. Earlier multilingual QA covered 960 directed 16-layout cases, Russian TextEdit/Spotlight, and 30/30 Arabic PC TextEdit runs.

## Open questions / blockers

- There is no test-mode license key available yet. Actual checkout, valid-key activation, and refund/revocation are unverified end to end. Do not claim the payment lifecycle is fully proven.
- Public/latest release and local appcast are v0.5.6/build 60. Choose a higher version and build above QA build 74, then test the exact signed/notarized package and Sparkle update; the current signed candidate is for data migration only.
- Prior UI risks remain: physical custom-shortcut behavior, Codex-in-Terminal stray-character rewrite, Firefox VM variability, and Arabic auto-correction without a functional dictionary.

## Next steps

1. Obtain a Lemon Squeezy test-mode key and exercise activation, restart, revocation, and offline behavior in a disposable VM.
2. Resolve or explicitly scope the remaining UI risks; bump version/build and create the exact signed/notarized release candidate.
3. Verify install and Sparkle update from public 0.5.6, stage to a small cohort, then consider broad distribution after review.

_Last updated: 2026-09-25 by Codex_
