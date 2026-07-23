# Third-Party Notices

FlicKey uses the following third-party software and techniques:

- **Sparkle** (https://github.com/sparkle-project/Sparkle) - in-app updates.
  MIT License, with components under BSD-2-Clause (bsdiff, signature
  verification) and a zlib-style license (Ed25519). Fetched via Swift Package
  Manager; not vendored in this repository.

- **HapticKey** (https://github.com/niw/HapticKey, MIT License) - FlicKey's
  trackpad haptics use the private-API technique pioneered by HapticKey
  (MultitouchSupport actuators). FlicKey's implementation
  (Sources/TrackpadActuator.swift) is written independently; this notice is
  attribution for the approach.

All sound effects and the application icon are original works by the FlicKey
author.
