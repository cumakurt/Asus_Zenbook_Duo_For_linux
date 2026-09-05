#!/bin/bash
# Generic Wayland session fallback.
ZENBOOK_PROFILE_LABEL="Generic / Wayland"
ZENBOOK_PROFILE_SOFTKBD=(squeekboard maliit-keyboard onboard)
ZENBOOK_PROFILE_TOUCH=none
ZENBOOK_PROFILE_MIRROR=none
ZENBOOK_PROFILE_WINDOWS=none
ZENBOOK_PROFILE_DISPLAY_TOOL="$(zenbook-backend-tool-name "${ZENBOOK_BACKEND:-}")"
