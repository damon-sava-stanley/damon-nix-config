#!/usr/bin/env bash
# Run from the graphical session while a USB-C monitor is blank, before rebooting.
set -u
umask 077

snapshot_dir=${DISPLAY_RESUME_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/display-resume}
mkdir -p "$snapshot_dir"
snapshot=$(mktemp "$snapshot_dir/snapshot.XXXXXXXX.log")

{
  printf 'Captured: %s\n' "$(date --iso-8601=seconds)"
  printf 'Boot ID: %s\n' "$(cat /proc/sys/kernel/random/boot_id)"
  printf 'Kernel: %s\n' "$(uname -r)"

  printf '\nPower sources:\n'
  for supply in /sys/class/power_supply/*; do
    [[ -f "$supply/type" ]] || continue
    if [[ -f "$supply/online" ]]; then
      printf '%s type=%s online=%s\n' \
        "${supply##*/}" "$(cat "$supply/type")" "$(cat "$supply/online")"
    fi
  done

  printf '\nDRM connectors (kernel detection):\n'
  for connector in /sys/class/drm/card*-DP-* /sys/class/drm/card*-eDP-*; do
    [[ -f "$connector/status" ]] || continue
    edid_bytes=$(wc -c < "$connector/edid" 2>/dev/null || printf '0')
    edid_sha256=-
    if (( edid_bytes > 0 )); then
      edid_sha256=$(sha256sum "$connector/edid" 2>/dev/null | cut -d ' ' -f 1)
    fi
    printf '%s status=%s enabled=%s first_mode=%s edid_bytes=%s edid_sha256=%s\n' \
      "${connector##*/}" \
      "$(cat "$connector/status")" \
      "$(cat "$connector/enabled")" \
      "$(head -n 1 "$connector/modes")" \
      "$edid_bytes" "$edid_sha256"
  done

  printf '\nUSB-C ports and alternate modes:\n'
  for port in /sys/class/typec/port[0-9]*; do
    [[ -d "$port" && -f "$port/data_role" ]] || continue
    printf '%s data_role=%s power_role=%s\n' \
      "${port##*/}" "$(cat "$port/data_role")" "$(cat "$port/power_role")"
    for device in "$port" "${port}-partner"; do
      [[ -d "$device" ]] || continue
      for mode in "$device"/*.?; do
        [[ -f "$mode/svid" ]] || continue
        printf '  %s svid=%s vdo=%s active=%s\n' \
          "${mode##*/}" "$(cat "$mode/svid")" \
          "$(cat "$mode/vdo")" "$(cat "$mode/active")"
      done
    done
  done

  printf '\nNiri outputs (compositor detection):\n'
  niri msg --json outputs 2>&1 || true

  printf '\nNiri connector and DRM messages from this boot:\n'
  journalctl -b _COMM=niri --no-pager -o short-iso 2>&1 |
    rg -i 'connector|device changed|pausing session|resuming session|drm|no mode|error' |
    tail -n 180 || true

  printf '\nRecent sleep operations from this boot:\n'
  journalctl -b \
    -u systemd-suspend.service \
    -u systemd-hibernate.service \
    -u systemd-suspend-then-hibernate.service \
    --no-pager -o short-iso 2>&1 |
    tail -n 60 || true

  printf '\nRelevant kernel messages from the last 30 minutes:\n'
  journalctl -b -k --since '30 minutes ago' --no-pager -o short-iso 2>&1 |
    rg -i 'hibernate|suspend|resume|i915|drm|ucsi|typec|thunderbolt|usb [0-9]+-[0-9]+:' |
    tail -n 160 || true
} > "$snapshot"

printf 'Display snapshot saved to %s\n' "$snapshot"
