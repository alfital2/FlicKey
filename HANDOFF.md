## Status

Public release 0.6.0/build 78 is prepared in `release/0.6.0` at `build/release-0.6.0-worktree`, based on the tested `fix/forced-layout-handoff` source. The universal Developer ID-signed app is built and verified, but NOT notarized or published. Public GitHub release and appcast remain 0.5.6/build 60. The user explicitly requested public release; automatic approval review separately blocked the Apple notarization upload, and an explicit approval question is pending. The root worktree has unrelated unfinished edits and must remain intact. The host is running public 0.5.6 from `build/released-v0.5.6`; QA build 77 remains in `/Applications/FlicKey.app`.

## Recent changes

- Prepared build 78 and release notes covering multilingual conversion, opt-in auto-fix beta improvements, layout memory/handoff fixes, and entitlement recovery.
- Fixed release packaging to notarize and staple the app before creating either distribution archive, so the Sparkle ZIP contains the app ticket; added an option to run release unit tests in Tart.
- Verified 575/575 unit tests and 5/5 live conversion/undo UI tests in `flickey-ui`. Built native Intel/Apple Silicon Release, re-signed Sparkle and app with Developer ID, verified signatures, clean entitlements, and absence of coverage instrumentation. Logs are in the release worktree's `build/release-*.log`.
- The password-based `flickey-notarize` profile fails. The existing API key at `~/.appstoreconnect/private_keys/AuthKey_UK666BK9RM.p8` works with issuer `15967b33-b9d4-439f-ac6b-bae719282d26` (found in the existing Framenook release manifest). No credential changes were made.
- Prepared isolated website branch `release/0.6.0` in `build/release-site-worktree`; only its footer version is changed so far. Nothing pushed or published.

## Open questions / blockers

- Await explicit user approval for uploading the compiled app to Apple's notarization service. Automatic review rejected it despite general release authorization; do not retry until approval arrives.
- Exact notarized Sparkle archive and distribution/update verification remain required before publishing.
- The dev worktree still contains a superseded provisional handoff guard and diagnostics; do not merge those over the tested forced-layout implementation. Earlier QA limitations include live messenger coverage requiring a logged-in guest and old converter fixtures assuming ABC/Hebrew only.

## Next steps

1. After Apple-upload approval, run the prepared `build/package-release.sh` from the release worktree with the existing API-key notarization environment variables. It resumes after successful build/sign/test and notarizes/staples the app and DMG.
2. Produce/sign the Sparkle ZIP and appcast using the packaging section of `scripts/release.sh`, targeting the isolated site worktree. Verify both packages, signatures against the public 0.5.6 key, notarization tickets, and update behavior in the VM.
3. Commit final handoffs, fast-forward/push main and tag v0.6.0, publish the GitHub assets and release notes, then push the website feed/version. Verify public downloads and live appcast before claiming completion.
4. Stop the test VM and refresh both repo handoffs with published URLs and verification results. Preserve the root and dev worktree's unrelated edits.

_Last updated: 2026-09-26 by Codex_
