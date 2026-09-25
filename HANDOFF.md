## Status

Local `dev` combines the multilingual layout converter, opt-in continuous-typing auto-fix, and entitlement hardening. It is now numbered 0.6.0/build 75 and installed on the user's Mac as a local Developer ID signed QA app at `/Applications/FlicKey.app`; it is not notarized or published. The app is running once, with `autoSwitchEnabled=1`, for several hours of manual use. The user's generous legacy grandfathering policy remains in place. `main`, the public GitHub release, and the appcast still serve 0.5.6/build 60.

## Recent changes

- Bumped `project.yml` to 0.6.0/build 75 so this combined feature release is visibly distinct from 0.5.6 and newer than local QA build 74.
- Built the exact `dev` source as Release, signed Sparkle and the app with the same Developer ID/team as the installed build, and verified the deep signature, bundle/build numbers, binary hash after install, and absence of coverage instrumentation.
- Backed up installed build 74 to `build/HostQA/Previous/InstalledBuild74-before-0.6.0.app`, replaced `/Applications/FlicKey.app`, and launched build 75. Confirmed one running process and preserved the enabled auto-fix preference.

## Open questions / blockers

- Manual host feedback on 0.6.0/build 75 is pending. Known QA limits include the Codex-in-Terminal stray-character rewrite, physical custom-shortcut behavior, Firefox VM variability, and Arabic auto-correction without a functional dictionary.
- Live license activation/deactivation passed in Tart, but checkout, provider-side revocation, and offline behavior remain untested. The Sparkle ZIP release flow needs an app stapling check/fix and an exact signed/notarized update test before customers receive it.
- No customer release, appcast update, push, or `main` merge has occurred. Build 75 is a local QA install only.

## Next steps

1. Collect several hours of host feedback, especially Russian, Arabic, other enabled layouts, and continuous auto-fix in everyday apps.
2. Resolve or clearly scope observed blockers; verify the exact notarized DMG and stapled Sparkle ZIP upgrading public 0.5.6 in Tart.
3. Merge the approved candidate to `main`, publish the GitHub assets and appcast, then monitor a small initial customer cohort.

_Last updated: 2026-09-25 by Codex_
