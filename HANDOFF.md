## Status

Local `dev` combines multilingual conversion and opt-in continuous-typing auto-fix with entitlement hardening. The user chose the generous legacy policy: surviving old preferences with no readable trial stamps qualify for free-forever grandfathering. Build 74 remains a QA install; no customer release, push, or change to `main` occurred. Project metadata is still 0.5.6/build 60, so the locally signed candidate is not a releasable update. A user-supplied live license passed provider and app activation in disposable Tart; the temporary activation was released and the VM stopped.

## Recent changes

- Tested a user-supplied live license without recording the key. Lemon Squeezy accepted activation for the expected store, validated the VM instance, and invalidated it after deactivation. In the app Support screen, activation unlocked a fresh trial and persisted across relaunch. A seeded expired trial unlocked and dismissed its paywall; Remove License restored expired state and paywall, deleted the isolated Keychain record, and returned provider activation usage to zero. The VM secret and test binaries were deleted.
- Stopped the disposable VM after removing its launch job, which had restarted the VM following the first stop command.

## Open questions / blockers

- Live activation and deactivation work for the supplied key, but checkout, provider-side revocation, and offline behavior remain untested. Do not claim the full payment lifecycle is proven.
- Public/latest release and local appcast are v0.5.6/build 60. Choose a higher version and build above QA build 74, then test the exact signed/notarized package and Sparkle update; the current signed candidate is for data migration only.
- Prior UI risks remain: physical custom-shortcut behavior, Codex-in-Terminal stray-character rewrite, Firefox VM variability, and Arabic auto-correction without a functional dictionary.

## Next steps

1. Resolve or explicitly scope the remaining UI risks; bump version/build and create the exact signed/notarized release candidate.
2. Verify checkout, provider-side revocation, and offline behavior when appropriate credentials or fixtures are available.
3. Verify install and Sparkle update from public 0.5.6, stage to a small cohort, then consider broad distribution after review.

_Last updated: 2026-09-25 by Codex_
