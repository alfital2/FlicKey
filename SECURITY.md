# Security policy

FlicKey runs with Accessibility privileges and observes keystrokes to do its job. That makes security reports especially welcome here.

## Reporting a vulnerability

Email **support@flickey.site**. Please do not open a public issue for anything you believe is exploitable; email first so a fix can ship before details are public.

Include what you found, how to reproduce it, and which FlicKey and macOS versions you tested. You can expect an acknowledgment within a few days. This is a one-person project, so complex fixes may take longer, but you will hear back and I will tell you when a fix ships.

## Scope

Things I care about most:

- Anything that lets another process read what FlicKey observes (typed text, the internal buffer).
- Anything that abuses FlicKey's Accessibility grant to act on other apps.
- Tampering with the update channel (Sparkle appcast or update signatures).

Trial or license circumvention on your own machine is not a security issue. The source is public and the licensing is client-side by design; see `LICENSE.md` for what the license does and does not allow.
