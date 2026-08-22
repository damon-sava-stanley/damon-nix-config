#!/usr/bin/env bash

set -euo pipefail

: "${BLUETOOTH_ENABLED:?BLUETOOTH_ENABLED must be set}"
: "${BLUETOOTH_POWER_ON_BOOT:?BLUETOOTH_POWER_ON_BOOT must be set}"
: "${BLUETOOTH_EXPERIMENTAL:?BLUETOOTH_EXPERIMENTAL must be set}"
: "${MAKO_ENABLED:?MAKO_ENABLED must be set}"
: "${WAYBAR_RIGHT_MODULES:?WAYBAR_RIGHT_MODULES must be set}"
: "${WAYBAR_BLUETOOTH_CLICK:?WAYBAR_BLUETOOTH_CLICK must be set}"

if [[ "$BLUETOOTH_ENABLED" != true ]]; then
  printf 'Bluetooth is not enabled\n' >&2
  exit 1
fi

if [[ "$BLUETOOTH_POWER_ON_BOOT" != true ]]; then
  printf 'Bluetooth is not powered on at boot\n' >&2
  exit 1
fi

if [[ "$BLUETOOTH_EXPERIMENTAL" != true ]]; then
  printf 'BlueZ experimental features are not enabled for battery reporting\n' >&2
  exit 1
fi

if [[ "$MAKO_ENABLED" != true ]]; then
  printf 'Mako is not enabled for Bluetooth pairing notifications\n' >&2
  exit 1
fi

if [[ " $WAYBAR_RIGHT_MODULES " != *' bluetooth '* ]]; then
  printf 'Waybar right modules do not include Bluetooth: %s\n' \
    "$WAYBAR_RIGHT_MODULES" >&2
  exit 1
fi

if [[ "$WAYBAR_BLUETOOTH_CLICK" != */bin/bzmenu\ -l\ fuzzel\ --interactive ]]; then
  printf 'Waybar Bluetooth click action is unexpected: %s\n' \
    "$WAYBAR_BLUETOOTH_CLICK" >&2
  exit 1
fi
