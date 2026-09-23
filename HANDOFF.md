## Status

`fix/auto-fix-global-retry` is an isolated branch/worktree from committed `main` (`4d1f6ff`). It now protects mid-sentence auto-fix with a short physical-input hold/replay transaction while retaining `main`'s broad keyboard fallback when AX editing or the new tap is unavailable. The original dirty worktree, prior failed integration branch, and host-installed FlicKey were not changed. The branch passed 530 unit tests and 8 live isolated-VM UI tests; it has not been merged or tried in the user's personal Mail/ChatGPT apps.

## Recent changes

- Added an optional pre-delivery input barrier that holds real keys/clicks during an edit and replays them FIFO after generated replacement keys; it uses a timestamp guard so a lagging monitor cannot edit an incomplete run. When unavailable, the original 150 ms quiet-gap path remains.
- Tagged FlicKey-generated keys so the tracker ignores only those, while replayed physical keys remain visible. Replay maps held keys to the newly selected layout, including Shift and Caps Lock.
- Fixed a generic AX false-positive: Firefox accepted an AX selected-text write but left its value unchanged and later duplicated the original words. Web-backed editors (detected by AXWebArea ancestry, not app name) now take the keyboard path; other AX writes require exact full-value verification and fail closed on uncertain mutation.
- Added real-key VM tests for Terminal, TextEdit, Safari and Firefox textarea/contenteditable, a no-barrier Terminal failover, and a corrected physical-key undo/learned-block story. The 120 ms Debug-only pause forces overlapping typing; tests assert actual field/DOM text and a mid-sentence switch.
- Final results: 530/530 headless units and 8/8 isolated-VM live UI tests passed on 2026-09-24. The dedicated `flickey-terminal-qa` VM was used; `flickey-ui` remained untouched.

## Open questions / blockers

- Apple Mail compose and the host ChatGPT app were not exercised; the VM has no Mail account, and personal app UI was deliberately not inspected. Do not claim universal app compatibility from the eight fixtures.
- AX-unreadable non-web editors still use the broad synthetic fallback as on main; their app-specific text services may introduce behavior not covered by these fixtures.

## Next steps

1. Review the branch diff and compare with the user's concurrent work before merging; this branch intentionally contains no prior integration branch's mandatory AX-focus policy.
2. If the user wants personal-app QA, prepare a signed test build and test only a temporary Mail draft / empty ChatGPT composer with explicit UI permission; leave existing content untouched.
3. Run the full release/QA matrix before merging to `main` or `dev`, including Spotlight/search safety and more layouts than ABC/Hebrew-PC.

_Last updated: 2026-09-24 by Codex_
