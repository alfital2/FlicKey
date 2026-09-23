## Status

The multilingual keyboard-layout conversion work now lives on a real branch, `feat/multilingual-layouts`, created directly from `main` at `4d1f6ff`. Its worktree is `build/multilingual-main-worktree`; it contains the isolated multilingual conversion/manual-shortcut changes and excludes the newer continuous-typing auto-fix work. All 559 host tests pass on this branch. The original root worktree remains on `fix/auto-fix-continuous-typing` with its pre-existing uncommitted combined changes, and main remains unchanged.

## Recent changes

- Moved the previously ignored `build/multilingual-only-src` snapshot into a dedicated main-based Git worktree so the multilingual feature has a reviewable, durable branch without mixing in continuous-typing edits.
- Copied only the snapshot's source, documentation, and test delta from main; excluded generated build output and snapshot-only notes.
- Regenerated the Xcode project and ran the full host suite on the new branch: 559 tests passed, including native 16-layout recovery and Russian regression coverage.

## Open questions / blockers

- The main-based branch has not had live editor or VM UI qualification. The earlier combined-branch UI results do not certify this isolated branch.
- Some languages lack functional macOS spell-check dictionaries; text-only reconstruction cannot resolve every physical-key ambiguity. IME support and broader editor coverage remain outside the verified scope.
- Prior review identified possible manual live-edit risks around stale on-screen text and fixed monitor-resume timing; assess these before release.

## Next steps

1. Run focused UI checks from `feat/multilingual-layouts` in ordinary editors and browsers, especially Russian conversion in both directions and text replacement.
2. Resolve any live-edit issues found, then rerun the relevant tests.
3. Review and merge the multilingual branch separately from the continuous-typing work when ready.

_Last updated: 2026-09-24 by GPT-6 / Codex_
