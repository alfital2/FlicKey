# Signed release trial gate

Run `bash scripts/verify-release-trial.sh build/Release/FlicKey.app` after signing the Release app and before publishing. This runs only in the disposable `flickey-ui` Tart VM (override with `FLICKEY_TEST_VM`). It never changes the host's trial or license records.

The gate launches the unchanged signed artifact, with no debug simulation. It checks the visible 30-day fresh-trial status, conversion during a trial, expired-trial purchase controls and blocked conversion, ignored QA unlock/reset arguments, clock-rollback protection, and expiry while the app stays open.

Fixture setup runs outside XCTest's sandbox. A VM-only helper, signed with the app's designated requirement, writes synthetic trial records through the native Keychain API. The helper and test suite stay outside the shipped app. Existing production licenses are not used or activated by this gate. Use a disposable guest: production preferences and trial fixtures in that guest are reset for each scenario.

Results are saved in the guest under `~/flickey-oss/build/ReleaseEntitlement-*.xcresult`. A successful run must complete all six cases. Previous interrupted runs or test setup failures are not release evidence.
