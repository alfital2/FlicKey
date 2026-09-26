## Status

FlicKey 0.6.0/build 78 is publicly released: https://github.com/alfital2/FlicKey/releases/tag/v0.6.0. The tag points to `c97a6df`; public main contains the tested forced-layout branch, release packaging fixes, and the production-trial gate. GitHub assets match local checksums, and https://flickey.site/appcast.xml is verified live at 0.6.0/build 78. The user authorized release conditional on trial enforcement; all six exact signed-release trial tests passed before Apple submission. Root and dev worktrees still contain unrelated unfinished changes and must be preserved.

## Recent changes

- Published the universal Intel/Apple Silicon Developer ID app after 575 unit tests, 5 conversion/undo UI tests, and 6 signed-release trial tests passed. Checks cover fresh 30-day access, active conversion, expired conversion blocked with purchase offered, ignored QA unlock/reset flags, clock rollback, and expiry while running.
- Added a mandatory pre-notarization release trial gate. Its helper and XCTest fixtures are VM-only and are never included in the shipped app. Fixture setup must run outside XCTest's sandbox and remove old preferences before importing each scenario; early setup failures were resolved before the successful six-case run.
- Verified the old QA unconditional unlock is absent. New users get 30 days; existing grandfathered users keep their promised access. No product entitlement code was changed in this release session.
- Fixed packaging to notarize/staple the app before both archives. Apple accepted app and DMG; tickets, signatures, Gatekeeper acceptance, universal architectures, clean entitlements, and absence of profiling were verified. Sparkle ZIP signature verifies against the public 0.5.6 key.
- Published website feed/version in site commit `e788434`; Pages deployment succeeded. Downloaded published assets and confirmed SHA-256: ZIP `7cd0b0e30d8604e363ac07dd70b2176fd2bbfbdd02152ad5139b52efa9cbae12`; DMG `339ca861650eb0e5bf160f91c3fe3dd1b7fcd8dc6c12fdaf8e5048810c429317`.

## Open questions / blockers

- No release blocker remains. Full live messenger coverage still needs a logged-in guest; old converter unit fixtures assume ABC/Hebrew. Actual update installation was not driven end-to-end; archive authenticity, compatibility key, notarization, public assets, and feed were verified.
- Root `fix/auto-fix-continuous-typing` and the dev worktree retain pre-existing unfinished work. Dev's provisional handoff guard is superseded by the implementation now in main; reconcile carefully in future work.
- The saved password notary profile fails. Existing API key `~/.appstoreconnect/private_keys/AuthKey_UK666BK9RM.p8` works with issuer `15967b33-b9d4-439f-ac6b-bae719282d26`. No credentials changed.

## Next steps

1. Monitor customer feedback for 0.6.0; preserve release artifacts/logs in `build/release-0.6.0-worktree`.
2. Continue unfinished feature work separately and reconcile dev with released main without overwriting dirty files.
3. The host is still running public 0.5.6 from `build/released-v0.5.6`; local QA build 77 remains in Applications. Use Check for Updates or the public DMG when ready to update the host.

_Last updated: 2026-09-26 by Codex_
