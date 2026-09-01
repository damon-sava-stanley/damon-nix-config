#!/usr/bin/env bash

set -euo pipefail

if [[ "$KEYD_ENABLED" != true ]]; then
  echo "keyd is not enabled" >&2
  exit 1
fi

if [[ " $KEYD_IDS " != *" * "* ]]; then
  echo "the dictation keyd configuration does not match all keyboards" >&2
  exit 1
fi

if [[ "$KEYD_RIGHTALT" != "layer(dictate)" ]]; then
  echo "Right Alt is not mapped to the dictate hold layer" >&2
  exit 1
fi

if [[ "$KEYD_DICTATE_LAYER" != true ]]; then
  echo "the keyd dictate layer is missing" >&2
  exit 1
fi

if [[ " $DAMON_GROUPS " != *" keyd "* ]]; then
  echo "damon cannot read keyd layer transitions" >&2
  exit 1
fi

if [[ "$KEYD_GROUP_DEFINED" != true ]]; then
  echo "the keyd socket group is not declared" >&2
  exit 1
fi

if [[ "$KEYD_SERVICE_GROUP" != keyd ]]; then
  echo "the keyd daemon does not start in its socket group" >&2
  exit 1
fi

if [[ "$LISTENER_WANTED_BY" != *"niri.service"* ]]; then
  echo "the dictation listener does not start with niri" >&2
  exit 1
fi

if [[ "$LISTENER_EXEC_START" != *"dictate-key-listener"* ]]; then
  echo "the graphical-session listener is not configured" >&2
  exit 1
fi

printf 'dictation configuration tests passed\n'
