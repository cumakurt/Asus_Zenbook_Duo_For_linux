#!/bin/bash
# Fallback profile when no DE×session match exists.
ZENBOOK_PROFILE_LABEL="Generic / ${ZENBOOK_SESSION:-unknown}"
ZENBOOK_PROFILE_SOFTKBD=(onboard squeekboard maliit-keyboard florence kvkbd)
ZENBOOK_PROFILE_TOUCH=none
ZENBOOK_PROFILE_MIRROR=none
ZENBOOK_PROFILE_WINDOWS=none
ZENBOOK_PROFILE_DISPLAY_TOOL="$(zenbook-backend-tool-name "${ZENBOOK_BACKEND:-}")"
