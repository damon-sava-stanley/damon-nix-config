#!/usr/bin/env bash

set -euo pipefail

: "${HOME_PACKAGE_NAMES:?HOME_PACKAGE_NAMES must be set}"
: "${NEOVIM_INIT_LUA:?NEOVIM_INIT_LUA must be set}"

if [[ " $HOME_PACKAGE_NAMES " != *" marksman "* ]]; then
  printf "Marksman is missing from Damon's Home Manager packages\n" >&2
  exit 1
fi

marksman_enable='vim.lsp.enable("marksman")'
if [[ "$NEOVIM_INIT_LUA" != *"$marksman_enable"* ]]; then
  printf 'Neovim does not enable the Marksman LSP configuration\n' >&2
  exit 1
fi
