#!/usr/bin/env bash

set -euo pipefail

if [[ " $HOME_PACKAGE_NAMES " != *" zmk-studio "* ]]; then
  echo "zmk-studio is missing from Damon's Home Manager packages" >&2
  exit 1
fi
