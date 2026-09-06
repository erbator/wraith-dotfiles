#!/usr/bin/env bash
# Alert chime shared by reminders and the Pomodoro timer. Targets the
# Headphones sink directly — the system default sink here points at an HDMI
# output with no speakers attached, so a plain `paplay` produces no sound.
set -uo pipefail

sound="/usr/share/sounds/freedesktop/stereo/complete.oga"
headphones_sink="alsa_output.pci-0000_00_1f.3-platform-sof-essx8336.HiFi__Headphones__sink"

paplay --device="$headphones_sink" "$sound" 2>/dev/null || paplay "$sound" 2>/dev/null || true
