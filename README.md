# Asus Zenbook Duo Linux Helper

Session-aware integration for the **ASUS Zenbook Duo UX8406CA** dual-screen laptop on modern Linux desktops (X11 and Wayland).

This project closes the gap between ASUS dual-panel hardware behaviour and what stock Linux desktop environments provide out of the box.

**Author:** [Cuma KURT](https://www.linkedin.com/in/cuma-kurt-34414917/)  
**Repository:** [github.com/cumakurt/Asus_Zenbook_Duo_For_linux](https://github.com/cumakurt/Asus_Zenbook_Duo_For_linux)  
**License:** [GPL-3.0-or-later](LICENSE)

---

## Problems this project solves

### 1. Detachable keyboard does not drive the bottom panel correctly

**Problem:** On the Zenbook Duo, attaching the physical keyboard should turn the bottom OLED into a keyboard base (single-panel mode). Detaching it should restore the second display. Linux does not do this automatically for most desktops.

**Solution:** The helper watches USB attach/detach events for the Duo keyboard (`ASUS Zenbook Duo Keyboard`, VID:PID `0b05:1bf2` / legacy `0b05:1b2c`) and enables or disables `eDP-2` through the correct display backend for your session.

### 2. Dual OLED layout is not managed by the desktop

**Problem:** Stock display settings do not reliably place `eDP-1` (top) above `eDP-2` (bottom) with the Duo’s native modes/refresh rates, especially after hotplug or rotation.

**Solution:** Explicit layout control:


| State             | Behaviour                                     |
| ----------------- | --------------------------------------------- |
| Keyboard attached | Top panel primary; bottom panel off           |
| Keyboard detached | Top + bottom stacked (`eDP-2` below `eDP-1`)  |
| Device rotated    | Both panels rotated and repositioned together |


Default panel modes: `2880x1800@120` (top and bottom; UX8406CA native).

### 3. Windows jump or disappear when the bottom panel turns off (X11)

**Problem:** When `eDP-2` is powered off, many window managers relocate windows unpredictably. Applications that were on the bottom panel can end up off-screen or on the wrong monitor.

**Solution:** On X11, before disabling the bottom output, the helper records windows whose centre point is on `eDP-2` (via `wmctrl` / EWMH) and moves them onto `eDP-1` after the RandR change.

### 3b. Dual OLED touch and stylus are not bound to the correct panel (X11)

**Problem:** Both ELAN touchscreens report absolute coordinates over the full virtual desktop, so a tap on the bottom OLED can move the cursor on the top panel (and vice versa).

**Solution:** After every layout change, the helper runs `xinput map-to-output` for touch + stylus + eraser devices: `ELAN9008` → `eDP-1`, `ELAN9009` → `eDP-2` (or `eDP-1` when the bottom panel is off). Relative touchpads are left alone. Manual remap: `zenbook touch`.

### 4. Bottom-panel brightness does not follow the top panel

**Problem:** The two OLEDs often expose separate backlight devices. Changing brightness in the desktop UI typically updates only the top panel (`intel_backlight`), leaving the ScreenPad/bottom panel dim or stuck.

**Solution:** The helper watches top-panel brightness changes (`inotify`) and mirrors the level to the bottom backlight (`card*-eDP-2-backlight` or `asus_screenpad`), scaled by each device’s `max_brightness`.

### 5. Detachable keyboard backlight has no first-class Linux control

**Problem:** The Duo keyboard backlight is driven by a vendor USB HID `SET_REPORT` command. There is no portable desktop setting for levels `0–3`, and older approaches ran a user-writable Python script via passwordless `sudo` (unsafe).

**Solution:** A small native C helper (`kbd-backlight`) sends the same HID report through `hidraw` first (safer for typing), falling back to USB `usbdevfs` when docked. Access uses a `udev` `uaccess` rule matching USB and Bluetooth uhid parents (`KERNELS=="0005:VID:PID.*"`). On undock the helper only unblocks Bluetooth (`rfkill`) and leaves HOGP to BlueZ — it does **not** call `bluetoothctl` connect/disconnect or GATT (those break HID: Connected without keys). When BT hidraw appears it may set `DETACH_BACKLIGHT` (default `3`) and re-enable Duo xinput nodes.

### 6. Wi-Fi / Bluetooth state fights the keyboard dock workflow

**Problem:** Docking/undocking can leave radios in an unexpected state relative to what the user had set while the keyboard was attached or detached.

**Solution:** The helper snapshots Wi-Fi (`nmcli`) and Bluetooth (`rfkill`) preferences and restores a consistent policy when the keyboard is attached or removed.

### 7. Rotation / tablet posture is ignored

**Problem:** Accelerometer orientation changes (laptop / tablet / tent) are not wired to dual-panel RandR/compositor layouts on most Linux setups.

**Solution:** `monitor-sensor` orientation events are mapped to layout commands (`normal`, `left-up`, `right-up`, `bottom-up`) and applied through the active display backend.

### 8. “Works on one desktop only” install scripts

**Problem:** Duo helpers are often hard-coded for GNOME+Wayland or a single distro. Installing them on MATE, KDE, Sway, Hyprland, COSMIC, etc. fails or breaks display control.

**Solution:** Automatic detection of:

- **OS / package manager** — `apt`, `dnf`, `pacman`
- **Desktop family** — MATE, GNOME, KDE, XFCE, Cinnamon, LXQt, Budgie, Pantheon, COSMIC, …
- **Session** — X11 or Wayland
- **Compositor** — Mutter, KWin, Hyprland, Sway/wlroots, COSMIC, …

Then a **profile** (`mate-x11`, `gnome-wayland`, `kde-wayland`, …) activates environment-specific command preferences (soft keyboard order, touch mapping, window move, mirror support) on top of the matching display **backend** (`xrandr` / `gdctl` / `kscreen-doctor` / `wlr-randr` / `hyprctl` / `cosmic-randr`).

Inspect the active matrix anytime:

```bash
zenbook detect
```

Overrides (debugging): `ZENBOOK_BACKEND_OVERRIDE`, `ZENBOOK_PROFILE_OVERRIDE`.

### 9. Fragile root/systemd display hooks

**Problem:** Systemd user/system units started outside the graphical session lack `DISPLAY` / `WAYLAND_DISPLAY` / `XAUTHORITY`, so `xrandr` / compositor tools fail silently.

**Solution:** XDG autostart under the real desktop user (with `OnlyShowIn` when known). Legacy GNOME/system sleep hooks and unsafe sudoers rules are cleaned up on install.

### 10. ScreenXpert-like Duo controls missing on Linux

**Problem:** Windows ships ScreenXpert (second-screen toggle, rotation lock, sharing modes, soft keyboard, BT keyboard battery). Stock Linux has none of that as one workflow.

**Solution:** CLI helpers that map to Linux tools:


| ScreenXpert idea                 | Linux helper                                               |
| -------------------------------- | ---------------------------------------------------------- |
| Second screen on/off             | `zenbook bottom on\|off\|toggle`                           |
| Rotation lock                    | `zenbook rotate-lock on\|off\|toggle`                      |
| Sharing: extend / clone / facing | `zenbook share extend\|duplicate\|facing\|reset`           |
| Virtual keyboard                 | `zenbook softkbd` (launches `onboard` / `squeekboard` / …) |
| Status + BT keyboard battery     | `zenbook status`                                           |


Full ScreenXpert UI, multi-finger gestures, App Switcher, and MyASUS are **not** reimplemented (Windows-only vendor stack).

---



## Hardware coverage (UX8406CA)

This helper targets **Duo dual-OLED + detachable keyboard** behaviour. It is **not** a full MyASUS / ScreenXpert replacement and does not drive every laptop subsystem.

### Covered (Linux userspace)


| Feature                                                     | Status                                     |
| ----------------------------------------------------------- | ------------------------------------------ |
| USB dock detect (`ASUS Zenbook Duo Keyboard` / `0b05:1bf2`) | Yes                                        |
| Bottom OLED enable/disable with dock                        | Yes                                        |
| Stacked dual-panel layout (`eDP-1` / `eDP-2`)               | Yes                                        |
| Native modes (default 2880×1800 @120 / @120) | Yes |
| Keyboard backlight 0–3 (USB HID)                            | Yes                                        |
| Dual-panel brightness sync                                  | Yes                                        |
| Accelerometer rotation layouts                              | Yes                                        |
| Rotation lock                                               | Yes                                        |
| Sharing: extend / duplicate (X11 mirror) / facing           | Yes (duplicate best on X11)                |
| Soft / on-screen keyboard launch                            | Yes (needs `onboard` or similar installed) |
| Dual OLED touch/stylus map-to-output (X11)                  | Yes (`ELAN9008`/`ELAN9009`)                |
| BT keyboard battery in `status`                             | Best-effort via BlueZ                      |
| Wi-Fi / Bluetooth preference restore                        | Yes                                        |
| Multi-DE backends (X11/GNOME/KDE/wlroots/Hyprland/COSMIC)   | Yes                                        |




### Not covered (out of scope or Windows-only)


| Feature                                             | Notes                                  |
| --------------------------------------------------- | -------------------------------------- |
| ScreenXpert overlay UI / widgets                    | Vendor Windows app                     |
| Multi-finger ScreenXpert gestures                   | Needs compositor gesture stack         |
| Task swap / window flick between panels             | Partial X11 rescue only; no gesture UI |
| Soft trackpad / handwriting pad                     | Use DE / onboard extras                |
| Kickstand                                           | Mechanical                             |
| Thunderbolt / Wi-Fi 7 / fans / battery charge limit | Kernel / firmware / other tools        |
| OLED HDR / colour profiles                          | Desktop colour management              |
| Fingerprint / camera / audio                        | Distro drivers; not this helper        |
| Wayland dual-touch binding                          | Compositor-dependent; X11 mapping only |
| GlideX / MyASUS updates                             | Windows / vendor cloud                 |


Kernel `hid-asus` quirks for Duo keyboard IDs complement this project; they are not installed by this repo.

---



## Supported display backends


| Backend    | Tool             | Typical environments                                      |
| ---------- | ---------------- | --------------------------------------------------------- |
| `x11`      | `xrandr`         | MATE, XFCE, Cinnamon, LXQt, GNOME/KDE on X11, classic WMs |
| `gnome`    | `gdctl`          | GNOME / Budgie / Pantheon Wayland                         |
| `kde`      | `kscreen-doctor` | Plasma Wayland                                            |
| `wlr`      | `wlr-randr`      | Sway, Wayfire, labwc, river, niri, other wlroots          |
| `hyprland` | `hyprctl`        | Hyprland                                                  |
| `cosmic`   | `cosmic-randr`   | System76 COSMIC                                           |


If the preferred tool is missing, the installer/runtime probes other backends in a safe order.

---



## Architecture

```text
install.sh                 # detect OS/DE → deps → install → udev → autostart
zenbook.sh                 # runtime entry: detect → backend → profile → watchers
lib/
  detect/                  # OS + desktop/compositor detection
  profile/                 # DE×session command preferences (mate-x11, gnome-wayland, …)
  profile.sh               # profile loader / softkbd prefs / capability flags
  install/                 # deps, autostart, udev, cleanup, C build
  backend/{x11,gnome,kde,wlr,hyprland,cosmic}/
  keyboard.sh              # USB keyboard detect + kbd-backlight
  touch.sh                 # X11 dual OLED touch/stylus map-to-output
  kbd-backlight.c          # native HID backlight (compiled at install)
  monitor.sh               # attach/detach orchestration
  brightness.sh            # panel brightness sync
  network.sh               # Wi-Fi / Bluetooth watchers
  features.sh              # share / bottom / softkbd / status
  rotate.sh                # accelerometer → layout
  cli.sh                   # ACPI / kbb / rotate / Duo CLI
  config.sh                # outputs, modes, paths
```

Profiles (`lib/profile/<de>-<session>.sh`) choose environment-specific command preferences; backends (`lib/backend/<tool>/`) implement the actual display IPC.

Runtime state lives under `$XDG_RUNTIME_DIR/zenbook/` (fallback `/tmp/zenbook/`).

---



## Requirements

- ASUS Zenbook Duo UX8406CA (or compatible dual `eDP-1` / `eDP-2` Duo)
- Linux with one of: `apt`, `dnf`, `pacman`
- Graphical session (X11 or supported Wayland compositor)
- `gcc`/`cc` to build `kbd-backlight` at install time

---



## Install

Run as your **normal desktop user** (not root). The script elevates only where needed.

```bash
chmod +x install.sh zenbook.sh uninstall.sh
./install.sh
```



### Uninstall

Removes only this application's installed artifacts (binary tree, autostart, udev rule, runtime state, obsolete hooks). Shared packages and the source tree are kept.

```bash
./uninstall.sh          # asks for confirmation
./uninstall.sh --yes    # no prompt
./uninstall.sh --dry-run
```



### Useful options


| Option          | Meaning                                                       |
| --------------- | ------------------------------------------------------------- |
| `--dry-run`     | Print detected OS/DE/backend and package plan; change nothing |
| `--backlight N` | Default keyboard backlight `0–3` (default: `3`)               |
| `--help`        | Show help                                                     |


Examples:

```bash
./install.sh --dry-run
./install.sh --backlight 2
```



### What install does

1. Detects OS, desktop, session, compositor, and display backend
2. Installs matching packages
3. Installs modules to `/usr/local/lib/zenbook/` and links `/usr/local/bin/zenbook`
4. Compiles `lib/kbd-backlight.c` → `kbd-backlight`
5. Writes XDG autostart for the detected desktop
6. Installs udev `uaccess` for USB + Bluetooth hidraw (`KERNELS==0005:…`)  
7. Keeps BlueZ `ExportClaimedServices` read-only (required for BT keyboard HID)  
8. Removes obsolete systemd/sudoers hooks from earlier helper installs  
9. Starts the helper in the current graphical session when possible

---



## Usage



### Automatic

After install, the helper starts with your desktop session and:

- reacts to keyboard attach/detach  
- syncs bottom-panel brightness  
- applies rotation from the accelerometer  
- keeps Wi-Fi/Bluetooth policy consistent

Logs: `/tmp/zenbook/zenbook.log` (and session start log when launched by the installer).

### CLI

```bash
zenbook                         # start watchers (normally via autostart)
zenbook help
zenbook status                  # dock, panels, backend, BT battery, locks
zenbook detect                  # DE / session / profile / capability matrix
zenbook touch                   # remap dual OLED touch/stylus (X11)
zenbook keyboard-heal           # re-enable Duo BT keyboard/touchpad nodes in X
zenbook kbb 2                   # keyboard backlight 0–3 (USB or BT hidraw)
zenbook softkbd                 # launch onboard/squeekboard if installed
zenbook bottom on|off|toggle    # force second screen
zenbook share extend|duplicate|facing|reset
zenbook rotate-lock on|off|toggle
zenbook normal|left-up|right-up|bottom-up
zenbook pre                     # ACPI-style: backlight off
zenbook post                    # ACPI-style: restore + re-check monitors
```

Optional soft keyboard package (not pulled by default): `onboard` (X11) or `squeekboard` (Wayland).

Environment overrides (optional):

```bash
export TOP_OUTPUT=eDP-1
export BOTTOM_OUTPUT=eDP-2
export TOP_MODE=2880x1800
export BOTTOM_MODE=2880x1800
export TOP_RATE=120
export BOTTOM_RATE=120
export DEFAULT_BACKLIGHT=3
export ZENBOOK_BACKEND_OVERRIDE=x11   # force backend (debug)
```

---



## Security model


| Old / unsafe pattern                        | This project                            |
| ------------------------------------------- | --------------------------------------- |
| NOPASSWD sudo on `/tmp/.../backlight.py`    | Removed on install                      |
| Root systemd unit driving GUI display tools | Avoided; XDG autostart as the user      |
| Python + pyusb runtime dependency           | Native `kbd-backlight` + udev `uaccess` |


The keyboard USB device is tagged for the active local seat so the backlight helper can open `/dev/bus/usb/...` without privilege escalation.

---



## Project layout (quick map)


| Path                                         | Role                           |
| -------------------------------------------- | ------------------------------ |
| [`install.sh`](install.sh)                   | Automatic detector + installer |
| [`zenbook.sh`](zenbook.sh)                   | Runtime entry point            |
| [`lib/detect/`](lib/detect/)                 | OS / desktop detection         |
| [`lib/backend/`](lib/backend/)               | Display backends               |
| [`lib/kbd-backlight.c`](lib/kbd-backlight.c) | Keyboard backlight (C)         |
| [`lib/monitor.sh`](lib/monitor.sh)           | Keyboard ↔ panel orchestration |
| [`lib/brightness.sh`](lib/brightness.sh)     | Dual-panel brightness sync     |


---



## Troubleshooting

**Bottom panel never enables/disables**  

- Confirm `eDP-1` / `eDP-2` exist (`xrandr -q`, `gdctl show`, `kscreen-doctor -o`, …).  
- Check `zenbook status`: both panels should report `(connected, on|off)`.  
- Dock is **USB only** — Bluetooth connected does not turn `eDP-2` off.  
- Confirm dock: `lsusb -d 0b05:1bf2` (or `lsusb | grep -i 'Zenbook Duo Keyboard'`).  
- Watch helper log while docking: `$XDG_RUNTIME_DIR/zenbook/zenbook.log` should show `Keyboard attached`.  
- Check backend: `./install.sh --dry-run` and the runtime log path above.  
- Ensure you are in a graphical session matching the detected backend.

**Keyboard backlight does nothing**  

- Replug the keyboard (USB) or toggle Bluetooth after install so udev `uaccess` applies.  
- Docked: `lsusb` should show `ASUS Zenbook Duo Keyboard` (`0b05:1bf2`).  
- Undocked: need BT HOGP hidraw (`HID_ID=0005:0B05:1BF3`). `getfacl /dev/hidraw*` should list your user.  
- Do **not** enable BlueZ `ExportClaimedServices=read-write` / GATT writes — they break typing.  
- Ensure `/usr/local/lib/zenbook/lib/kbd-backlight` is executable.  
- Manual: `zenbook kbb 3`.

**Undocked keys/touchpad die / BT keeps reconnecting**  

- Log proof: after bluetoothd restart / disconnect loops, BlueZ no longer auto-HOGPs this keyboard (16:19 undock: zero BlueZ activity for ~35s).  
- Current helper: brief auto wait, then **one** `bluetoothctl connect` — **never** disconnect/GATT. Success = uhid/`xinput` without Primax, not merely Connected.  
- Reinstall: `./install.sh`. Undock and wait ~15s. Log should show `BT connect once` then `BT HID ready`.  
- Keyboard left-side BT switch ON; paired/trusted.  
- Conflicting `Keyboard Mouse` node is disabled when Touchpad appears (`ZENBOOK_KEEP_DUO_MOUSE=1` to keep it).

**Undocked touchpad does nothing**  

- Confirm BT HID: `bluetoothctl devices Connected` lists the Duo keyboard **and** `xinput` shows non-Primax Duo Touchpad.  
- Then `zenbook keyboard-heal`.

**Brightness sync only on one panel**  

- Check `/sys/class/backlight/` for `intel_backlight` and a bottom device (`*-eDP-2-backlight` or `asus_screenpad`).  
- Install `brightnessctl` if write access to sysfs is restricted.

**Wrong desktop backend**  

```bash
ZENBOOK_BACKEND_OVERRIDE=x11 /usr/local/bin/zenbook
```

Use only for debugging; prefer fixing session type / installed tools.

---



## Credits

- **Author:** Cuma KURT  
  - LinkedIn: [https://www.linkedin.com/in/cuma-kurt-34414917/](https://www.linkedin.com/in/cuma-kurt-34414917/)  
  - GitHub: [https://github.com/cumakurt/Asus_Zenbook_Duo_For_linux](https://github.com/cumakurt/Asus_Zenbook_Duo_For_linux)
- Keyboard HID backlight protocol based on work by **Alesya Huzik** (BSD-2-Clause).  
- Dual-panel UX adapted for multi-desktop Linux (MATE/X11 origins extended to GNOME, KDE, wlroots, Hyprland, COSMIC).

---



## License

This project is licensed under the **GNU General Public License v3.0 or later** — see [LICENSE](LICENSE).

The keyboard backlight helper retains attribution for the BSD-2-Clause HID protocol work it adapts; BSD-2-Clause is compatible with GPL-3.0.
