# Isolated macOS UI tests

The dedicated Tart VM is named `flickey-ui`. Its macOS desktop owns the test
mouse, keyboard, input sources, and clipboard. The host runner never invokes
Xcode tests locally.

```sh
scripts/tart.sh start   # background VM, no host window/audio/clipboard sharing
scripts/tart.sh start-visible # open the guest desktop in a Tart window
scripts/tart.sh status
scripts/tart.sh smoke   # one Settings test, inside the VM
scripts/tart.sh unit    # unit suite, inside the VM
scripts/tart.sh ui      # standard UI suite, inside the VM
scripts/tart.sh browser-ui         # deterministic local-site Safari suite
scripts/tart.sh browser-ui-firefox # deterministic local-site Firefox suite
scripts/tart.sh teams-ui           # live Teams compatibility suite (never sends)
scripts/tart.sh stop    # release the VM's CPU and memory
```

To observe a run, use `start-visible`, move the Tart window to another macOS
Space, and run `scripts/tart.sh smoke` or `scripts/tart.sh ui` from a host
Terminal. The same VM and test runner are used in visible and background modes.
App launches, clicks, typing, clipboard changes, and input-source changes happen
on the guest desktop shown in the Tart window. Guest app activation does not
switch the host to that Space. Avoid clicking or typing inside the Tart window
while a test is running, because that intentionally sends input to the guest and
can interfere with the test.

Wait for the guest to boot before issuing test commands. `start` does not install
or clone a missing VM. The Tart binary defaults to
`/Applications/tart.app/Contents/MacOS/tart`; override `FLICKEY_TART_BIN` if needed.

Tests receive a staged copy of Sources, Resources, Tests, UITests, scripts,
project.yml, and FlicKey.entitlements. The guest builds its own copy. Host build
products, signing credentials, and personal settings are not shared. The host's
Xcode application is copied through an archive stream during setup. No additional
tvOS, watchOS, or visionOS simulator runtimes are installed by setup.

Smoke and full-suite `.xcresult` reports plus transcripts are copied to
`build/tart/results/`. The working copies also remain in
`/Users/admin/flickey-oss/build` inside the guest. VM startup output is at
`/private/tmp/flickey-tart-vm.log` (outside Documents so the background launcher
can open it before starting Tart).

For initial guest provisioning, run `scripts/tart.sh setup`. This installs the
host's Xcode, enables development tools, installs xcodegen, prevents guest sleep,
enables ABC and Hebrew-PC, installs Firefox and Microsoft Teams, and provisions
Accessibility for the fixed FlicKey and XCTest-runner build paths. The guest must
have an unlocked desktop session. Re-run setup if its test build location changes.

The standard UI suite excludes opt-in browser and Teams integration suites.
Browser tests use local `*.localhost` pages and do not require internet access.
Teams still requires a guest login and configured test chats, but the suite does
not send messages or type into a compose box it cannot inspect.
For the two-chat memory story, provide the exact display names of two harmless
chats (they are forwarded only into the guest test process):

```sh
TEAMS_CHAT_A="First Contact" TEAMS_CHAT_B="Second Contact" scripts/tart.sh teams-ui
```

Physical haptic feedback still requires testing on real hardware.
