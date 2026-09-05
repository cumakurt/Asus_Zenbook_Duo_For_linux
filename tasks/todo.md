# Todo

## Hardware coverage (UX8406CA)

- [x] Research ASUS/official ScreenXpert + UX8406CA exclusive features
- [x] Map features vs current helper (honest gap analysis)
- [x] Add Duo CLI: status, bottom, share, rotate-lock, softkbd
- [x] X11 mirror (`--same-as`) for share duplicate
- [x] Respect rotate-lock in watcher + CLI
- [x] Document hardware coverage matrix in README

## Keyboard dock fix (2026-09-05)

- [x] Recursive `inotifywait -r` on `/dev/bus/usb` (device nodes are under bus subdirs)
- [x] Transition-only monitor apply (ignore unrelated USB noise)
- [x] Harden USB detect: product `ASUS Zenbook Duo Keyboard` + VID:PID `0b05:1bf2` / `0b05:1b2c`
- [x] udev rules always include known VID:PIDs (even if keyboard absent at install)
- [x] `zenbook status` shows top/bottom `(connected|disconnected, on|off)`
- [x] On undock: max keyboard backlight (`DETACH_BACKLIGHT=3`) via USB race + BT hidraw retries
- [x] X11 dual touch/stylus `map-to-output` (`ELAN9008`→eDP-1, `ELAN9009`→eDP-2)
- [x] DE×session profiles (`mate-x11`, `gnome-wayland`, …) with specialized command prefs

## Review

- Verdict: this app covers **Duo dual-screen + keyboard** Linux gaps, not the full laptop stack or ScreenXpert UI.
- Implemented Linux equivalents for second-screen toggle, rotation lock, sharing modes, softkbd launch, and status/BT battery.
- Remaining Windows-only: gestures, App Switcher/Flick, widgets, MyASUS/GlideX.
- General hardware (Wi-Fi 7, TB, fans, HDR, fingerprint, pen) stays with kernel/DE/other tools.
- Dock root cause: non-recursive USB inotify missed `0b05:1bf2` plug events; panel logic itself was fine once triggered.
