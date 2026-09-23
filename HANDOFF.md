## Status

`fix/auto-fix-global-retry` (implementation commit `ca7d6d4`) remains isolated from `main` and other dirty worktrees. Its auto-fix change passed 530 unit tests and 8 isolated-VM live UI tests. A locally signed Release QA build with overridden build number 72 is now installed and running at `/Applications/FlicKey.app`; the previous installed build 60 is preserved under this worktree's `build/HostQA/Previous/`. FlicKey currently shows an Accessibility Access Required alert, so the new host install has not yet been proven functional in the user's apps. It has not been merged.

## Recent changes

- Built this branch as local Release QA build 72 with the existing Developer ID identity; strict deep signature verification passed, and the installed binary's SHA-256 and CDHash match the built product.
- Made a verified recoverable copy of installed build 60, then moved the old app to `build/HostQA/Previous/InstalledOriginal.app` before installing build 72 at `/Applications/FlicKey.app`.
- Gracefully closed the older FlicKey processes. Verified exactly one FlicKey process running, from `/Applications/FlicKey.app` (build 72); did not alter the other session's `flickey-ui` VM.
- Inspected the launched app UI: it shows an Accessibility Access Required alert. No Accessibility/TCC permission was granted or changed in this session.

## Open questions / blockers

- User action or explicit approval is needed to enable FlicKey in System Settings › Privacy & Security › Accessibility; auto-fix cannot be meaningfully tested on the host while that alert is present.
- Apple Mail compose and the host ChatGPT app are still untested. The eight VM fixtures are not proof of universal app compatibility.
- This is a locally signed, unnotarized QA build, not a distributable release. The build number 72 was an Xcode build-setting override, not a source version change.

## Next steps

1. Have the user enable Accessibility for the installed FlicKey, or obtain explicit approval before doing it through the UI; verify the alert clears and auto-fix is enabled in the app's settings.
2. Let the user test build 72 in the apps that previously failed; if authorized, run controlled tests in temporary Mail/ChatGPT fields without inspecting existing private content.
3. Review the branch against concurrent work and run the remaining release/QA matrix before merging. To restore build 60, first quit build 72 and move the preserved app back to `/Applications/FlicKey.app`.

_Last updated: 2026-09-24 by Codex_
