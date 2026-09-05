#!/bin/bash
# Shared X11 family defaults (MATE/XFCE/Cinnamon/LXQt/… on X11 use xrandr).
ZENBOOK_PROFILE_LABEL="X11 family / ${ZENBOOK_DE:-unknown}"
ZENBOOK_PROFILE_SOFTKBD=(onboard florence maliit-keyboard kvkbd squeekboard)
ZENBOOK_PROFILE_TOUCH=x11
ZENBOOK_PROFILE_MIRROR=x11
ZENBOOK_PROFILE_WINDOWS=wmctrl
ZENBOOK_PROFILE_DISPLAY_TOOL=xrandr
