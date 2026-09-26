# FlicKey 0.6.0

- Improved wrong-layout text conversion across more macOS keyboard layouts, including Russian, Arabic PC, accented letters, and combining characters.
- More reliable auto-fix when you keep typing during a correction, with safeguards when switching apps, browser tabs, or keyboard layouts. Auto-fix remains an opt-in beta.
- Fixed remembered layouts being overwritten by delayed layout changes from another app.
- Fixed pinned app layouts, including Terminal's English rule, being lost during app switching.
- Improved trial-state recovery and license activation reliability while preserving existing early users' free access.

Requires macOS 13 or later. Includes native Apple Silicon and Intel support.

Automatic correction depends on the dictionaries available in macOS. Static keyboard-layout conversion does not support Chinese, Japanese, or Korean composition input methods.

Existing users can choose **Check for Updates** in FlicKey. For a new installation, download `FlicKey.dmg` and drag FlicKey to Applications.
