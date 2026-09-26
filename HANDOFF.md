## Status

Release 0.6.0/build 78 is prepared in `release/0.6.0` at `build/release-0.6.0-worktree`, based on tested `fix/forced-layout-handoff` source. The user approved public release and Apple notarization conditional on production trial enforcement. That condition is verified: all six exact signed-release trial UI cases passed. Apple notarization/package generation is in progress; nothing has been published yet. Public GitHub release and appcast remain 0.5.6/build 60. Root and dev worktrees contain unrelated unfinished changes; preserve them.

## Recent changes

- Prepared build 78 and release notes for multilingual conversion, opt-in auto-fix beta, layout memory/handoff fixes, and entitlement recovery.
- Verified 575/575 unit tests, 5/5 live conversion/undo UI tests, and 6/6 tests of the actual signed release: fresh 30-day trial, active conversion, expired conversion blocked and purchase offered, QA unlock/reset flags ignored, clock rollback, and expiry while running. Successful log: `build/release-0.6.0-worktree/build/release-entitlement-tests.log`.
- Added a mandatory pre-notarization trial gate to `scripts/build-dmg.sh`. The VM-only helper/test fixtures are outside the shipped app. Tests must seed data outside XCTest's sandbox and clear old preferences before importing each fixture.
- Fixed packaging to notarize/staple the app before making either archive. Release is universal Intel/Apple Silicon, Developer ID signed, with clean entitlements and no profiling instrumentation. Its executable SHA-256 is `208014392469947a2617da399aaeb73d5d0ce7ca7aad49d8f93052735c79547b` before stapling (stapling does not change this binary).
- The old QA entitlement bypass was removed previously in `7550993`; release test seams are compiled out. Existing grandfathered users keep their promised access; new users get 30 days.
- Working notarization auth: existing API key `~/.appstoreconnect/private_keys/AuthKey_UK666BK9RM.p8`, issuer `15967b33-b9d4-439f-ac6b-bae719282d26`. The saved password profile fails. No credentials changed.

## Open questions / blockers

- Await Apple notarization and final archive verification, then publish. No user approval remains outstanding.
- Isolated website branch is in `build/release-site-worktree`; footer version is prepared, appcast is generated after packaging.
- Prior QA limits remain: full live messenger coverage needs a logged-in guest; old converter unit fixtures assume ABC/Hebrew. Superseded provisional dev-worktree handoff changes must not overwrite the tested implementation.

## Next steps

1. Finish the running `build/package-release.sh`, then run `build/package-update.sh` to sign the Sparkle ZIP and write the isolated site's feed.
2. Verify archive signatures/tickets and the signature against the public 0.5.6 update key; publish main/tag/GitHub assets and the site feed/version.
3. Verify live downloads/appcast, refresh handoffs with results, and stop the VM. Host remains on public 0.5.6 from `build/released-v0.5.6`; build 77 stays installed in Applications.

_Last updated: 2026-09-26 by Codex_
