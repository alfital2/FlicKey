# FlicKey

FlicKey is a macOS menu bar app for people who type in more than one language. When you type into the wrong keyboard layout, it fixes the text and switches the layout for you.

If you type Hebrew and English you know the moment: you write a whole sentence, look up, and it says `akuo vnmc` instead of שלום המצב. FlicKey catches this as it happens, converts what you typed, and flips the keyboard so you can keep going.

## What it does

- Fixes wrong-layout typing automatically. After two confidently wrong words it converts the whole run, including names and short words that dictionaries miss, and switches the layout.
- Double-tap Shift converts the current text on demand.
- Double-tap Option undoes an auto-fix and switches back. Undo the same word twice and FlicKey stops touching that word.
- Remembers your layout per app, per website, and per chat. Move from a Hebrew WhatsApp thread to an English work chat in Teams and the keyboard follows.
- Discovers installed browsers automatically, including Firefox, Zen, Safari, Chrome, and compatible forks.
- Plays a click when a fix lands, with a few sounds to choose from, and can tap the trackpad so you feel the switch without looking.

Everything runs locally. FlicKey has no server, no account, and it does not send what you type anywhere.

## Install

Download the app from [flickey.site](https://flickey.site), drag it to Applications, and grant Accessibility access when asked. FlicKey needs Accessibility because that is the macOS mechanism for reading the text field it is fixing and for observing keystrokes. Requires macOS 13 or later.

Firefox-based browsers also use macOS Accessibility to expose the selected tab's address because Gecko does not provide AppleScript tab support. If Firefox's advanced `accessibility.force_disabled` preference is set to `1`, per-site memory cannot read its tabs and quietly keeps the last known site; the rest of FlicKey continues to work.

## Build from source

You need Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
xcodegen generate
open FlicKey.xcodeproj
```

The project file is generated from `project.yml`. Note that `project.yml` pins the author's signing identity; switch it to your own team (or automatic signing) to build locally. Accessibility permission is tied to the signing certificate, so you grant it once per identity.

Run the tests with:

```sh
xcodebuild test -scheme FlicKey
```

See `TESTING.md` for the full testing story, including the UI test suite and what still needs a manual pass.

## A note on the haptics

Trackpad taps use a private macOS framework (the technique comes from [HapticKey](https://github.com/niw/HapticKey)). Apple could break this in any release. The code resolves everything dynamically and falls back to standard haptic feedback if the private API goes away.

## License

FlicKey is **source available** — the full source is published under the FlicKey Source License (see `LICENSE.md`), which is not an OSI-approved license. You may study it, make private builds, and create source-only forks for experimentation or contributions. You may not distribute a FlicKey-derived app, product, or service without prior written permission. Independently created software that copies no protected FlicKey code is outside the license. If FlicKey saves you time, [a one-time purchase](https://flickey.site) keeps it maintained.
