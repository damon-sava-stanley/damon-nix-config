#!/usr/bin/env bash

set -euo pipefail

: "${BRAVE_EXTENSION_IDS:?BRAVE_EXTENSION_IDS must be set}"

assert_extension_is_configured() {
  local extension_id="$1"

  if [[ " $BRAVE_EXTENSION_IDS " != *" $extension_id "* ]]; then
    printf 'Brave extension is not configured: %s\n' "$extension_id" >&2
    exit 1
  fi
}

assert_extension_is_configured "eimadpbcbfnmbkopoojfekhnkhdbieeh"
assert_extension_is_configured "oboonakemofpalcgghocfoadofidjkkk"
