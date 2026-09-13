#!/usr/bin/env bash

set -euo pipefail

: "${DAMON_SHELL_PACKAGE:?DAMON_SHELL_PACKAGE must be set}"
: "${NIXOS_FISH_ENABLED:?NIXOS_FISH_ENABLED must be set}"
: "${HOME_FISH_ENABLED:?HOME_FISH_ENABLED must be set}"

if [[ "$DAMON_SHELL_PACKAGE" != fish ]]; then
  printf "Damon's login-shell package is not Fish: %s\n" "$DAMON_SHELL_PACKAGE" >&2
  exit 1
fi

if [[ "$NIXOS_FISH_ENABLED" != true ]]; then
  echo "Fish is not enabled in the NixOS configuration" >&2
  exit 1
fi

if [[ "$HOME_FISH_ENABLED" != true ]]; then
  echo "Fish is not enabled in Damon's Home Manager configuration" >&2
  exit 1
fi
