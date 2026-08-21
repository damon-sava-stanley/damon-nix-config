#!/usr/bin/env bash

set -euo pipefail

: "${HOME_CONFIG:?HOME_CONFIG must be set}"
: "${WAYBAR_SWITCH_METHOD:?WAYBAR_SWITCH_METHOD must be set}"

if [[ "$WAYBAR_SWITCH_METHOD" != restart ]]; then
  printf 'Waybar switch method is %q, expected restart\n' \
    "$WAYBAR_SWITCH_METHOD" >&2
  exit 1
fi

if ! grep -Fq \
  'systemctl --user --no-block try-restart waybar.service || true' \
  "$HOME_CONFIG"; then
  printf 'Theme refresh does not queue a Waybar service restart\n' >&2
  exit 1
fi

if grep -Eq 'pkill[[:space:]]+-x[[:space:]]+-USR2[[:space:]]+waybar' \
  "$HOME_CONFIG"; then
  printf 'Theme refresh still sends Waybar SIGUSR2\n' >&2
  exit 1
fi
