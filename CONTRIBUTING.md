# Contributing

Thanks for wanting to improve FlicKey. Small fixes, bug reports, and language support are all useful.

## Before you start

Open an issue first for anything bigger than a small fix. FlicKey's core is timing-sensitive (a passive keystroke monitor cannot block or reorder keys), and several designs that look simpler were tried and reverted. An issue conversation can save you a rewritten weekend.

## Building and testing

See the README for build steps. Before opening a PR:

```sh
xcodebuild test -scheme FlicKey
```

All tests must pass. If you change detection or conversion logic, add a test that fails without your change. The unit suite is fast and headless; the UI suite (`scripts/run-ui-tests.sh`) takes over the screen for a couple of minutes, so run it when your change touches the Settings window.

A note on the Teams UI test: it needs a real Microsoft Teams tenant with two chats. Set `TEST_RUNNER_TEAMS_CHAT_A` and `TEST_RUNNER_TEAMS_CHAT_B` to chat names that exist in your tenant.

## What gets merged

- Fixes with a reproducing test, almost always.
- New language support, gladly, if the macOS spell checker actually works for that language (several ship broken dictionaries; the code gates on this).
- Refactors without behavior change, rarely. The comment density in this codebase is deliberate; match it.

## Licensing of contributions

By submitting a contribution you agree that it is licensed under the FlicKey License (see `LICENSE.md`) and that the FlicKey author may include it in official FlicKey releases, including the paid builds. If you are not comfortable with your code appearing in a paid build, please do not submit it.
