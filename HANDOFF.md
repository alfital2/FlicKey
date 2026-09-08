## Status

The source behind the user-approved reverted Firefox build 43 is now the official baseline. The Firefox cold-start fix is committed at `b5a3b82` on `fix/firefox-cold-start-ax`, based directly on build-43 source commit `d0027db`. The abandoned arm64/signing experiment is preserved as `reverted/firefox-build44-arm64-signing-experiment`. A Developer-ID-signed local build of `b5a3b82` is running from `/private/tmp/flickey-firefox-coldstart-fixed.xlbY4M/Release/FlicKey.app` for live validation.

## Recent changes

- Used privacy-safe unified logs to confirm Firefox could remain tab-unaware indefinitely after cold launch, then recover only after focus/unfocus forced a lifecycle reset.
- Fixed the cause: an AXRole request is no longer treated as proof that Firefox's asynchronous Accessibility tree is ready; failed reads remain retryable.
- Invalidated and rediscovered cached Gecko web areas when they remain alive but lose their URL, preventing a stale cache from becoming permanent.
- Added four bounded rapid retries over 750 ms for Accessibility-backed browsers, with recovery logging and cancellation on app changes.
- Added retry-policy regression tests. All 488 unit tests and all 36 focused browser tests pass.

## Open questions / blockers

- The user still needs to validate a true Firefox quit/relaunch without focus cycling; the running build emits `browser AX not ready` and `browser AX ready` recovery events for timing evidence.
- A distributable signed DMG still needs a fresh artifact cycle after live behavior is approved. Earlier build-43 DMGs failed signature verification in the VM and must not be reused.

## Next steps

1. Cold-relaunch Firefox and verify remembered tabs become active immediately without leaving Firefox.
2. Inspect the recovery events to measure actual readiness latency and adjust the bounded retry schedule only if evidence requires it.
3. After approval, merge `b5a3b82` into the official development line and create a newly numbered, serial-signed artifact with fresh-copy and mounted-DMG verification gates.

_Last updated: 2026-09-09 by Codex_
