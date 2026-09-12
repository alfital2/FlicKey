## Status

`dev` now includes two explicit input behaviors: fixed and persistent last-used memory. Ordinary apps remember app-wide, browsers per website, and supported chat apps per conversation. Existing saved source choices migrate conservatively as fixed rules. Version 0.5.5 (build 59) removes the rejected reset-on-launch experiment and is running locally for QA.

## Recent changes

- Split fixed layout selection from learning: “Always” can no longer be overwritten by manual or automatic source changes.
- Added persistent “Remember last used” for ordinary apps while retaining persistent per-website and per-conversation memory for browsers/chat apps.
- Automatically discovered/learned ordinary apps now enter persistent memory mode instead of becoming ambiguous fixed rules.
- Removed reset-on-launch and its session-memory implementation; any build 57 test setting safely becomes a fixed rule using its selected default.
- Bumped the release to 0.5.5 (59); the full 517-test unit suite passes.
- Packaged a unique universal Developer-ID-signed build 59 QA DMG; the exact mounted app passes strict nested signature checks for both architectures. The local-transfer artifact is not notarized.
- Added an upgrade-contract regression that seeds released-build preferences and proves explicit app rules, custom apps, hidden rows, site memory, and conversation memory survive migration unchanged.
- Made both test runners override the developer-specific project identity with local ad-hoc signing, so unit/UI suites build on clean Macs and VMs without release-signing credentials; focused tests and the full UI target build pass with that override.
- Added VM test entry points that put a small `xcodebuild` wrapper first on `PATH`; it forces ad-hoc signing and disables hardened runtime only for disposable test runners. This avoids missing-certificate, mixed-Team-ID, and VirtioFS-xcconfig parsing failures; a real UI smoke test passes. `test-vm2.sh` exists solely to bypass the guest's cached first wrapper filename.

## Open questions / blockers

- Manual QA of both modes is still required before merging the feature branch into `dev`.
- True per-tab or per-document identity is not part of this change; browser memory remains per website.

## Next steps

1. Manually verify fixed and persistent modes on an ordinary app.
2. Verify persistent per-website Firefox behavior and per-conversation Teams/Slack behavior.
3. Prepare the notarized release only after QA approval.

_Last updated: 2026-09-12_
