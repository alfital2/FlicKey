## Status

Branch `fix/app-memory-echo` (worktree `build/app-memory-echo-worktree`, off local `dev`) fixes "Remember last used" apps learning another app's forced layout under rapid app switching. It is installed on the user's Mac as local Developer ID signed QA build 0.6.0/76 (build number overridden on the command line only; `project.yml` still says 75). Build 75 is backed up at `build/app-memory-echo-worktree/build/FlicKey-75-backup.app`. Nothing pushed; `main`, public GitHub, and the appcast remain 0.5.6/build 60. The root worktree's uncommitted `fix/auto-fix-continuous-typing` work and the `dev` worktree's uncommitted UITest edits were left untouched.

## Recent changes

- Root cause (confirmed in the unified log at 23:48:17): Terminal forced English, WhatsApp activated ~70ms later, and Terminal's delayed English echo landed while WhatsApp was frontmost. AppWatcher's one-shot per-owner ignore token had already been overwritten by WhatsApp's apply, so it saved English as WhatsApp's last-used layout.
- Added `ProgrammaticSwitchLedger`: a shared 0.8s window of recent FlicKey-made switches (target plus pre-switch source). AppWatcher and `ConversationMemoryCore` (browser sites, Teams) record through it and ignore any echo in it, including echoes from other owners. The Chrome↔WhatsApp variant in the same log is the cross-owner case.
- `ProgrammaticSwitches.apply` re-issues a switch when an earlier request for a different source is still in flight, even if the current source already reads as the target.
- Accepted trade-off: a genuine user change within 0.8s of arriving, to a source involved in a recent switch, is not learned.

## Open questions / blockers

- The user's WhatsApp memory is still `ABC` from the pre-fix corruption; they need to set Hebrew once in WhatsApp.
- Auto-fix and hotkey conversion switches are deliberately not recorded, so they are still learned as the app's layout (unchanged behavior).

## Next steps

1. User QA of build 76: rapid WhatsApp↔Terminal and WhatsApp↔Chrome switching should keep WhatsApp Hebrew.
2. If it holds, merge `fix/app-memory-echo` into `dev` and bump the real build number there.
3. Continue the 0.6.0 release plan (notarized DMG, Sparkle update test from 0.5.6).

_Last updated: 2026-09-25 by Claude Code (Opus 5.5)_
