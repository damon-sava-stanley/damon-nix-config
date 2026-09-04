#!/usr/bin/env bash

set -euo pipefail

if [[ " $HOME_PACKAGE_NAMES " != *" zmk-studio "* ]]; then
  echo "zmk-studio is missing from Damon's Home Manager packages" >&2
  exit 1
fi

if [[ " $DAMON_GROUPS " != *" dialout "* ]]; then
  echo "Damon is missing the dialout group needed for ZMK Studio USB access" >&2
  exit 1
fi
