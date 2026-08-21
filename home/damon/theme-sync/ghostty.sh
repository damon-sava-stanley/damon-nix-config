#!/usr/bin/env bash

set -euo pipefail

mode="${1:-}"
: "${ghostty_theme_file:?ghostty_theme_file must be set}"

case "$mode" in
  dark)
    theme="iTerm2 Solarized Dark"
    ;;
  light)
    theme="iTerm2 Solarized Light"
    ;;
  *)
    printf 'unsupported Ghostty theme mode: %s\n' "$mode" >&2
    exit 2
    ;;
esac

mkdir -p "$(dirname -- "$ghostty_theme_file")"
temporary_file="$ghostty_theme_file.tmp.$$"
trap 'rm -f -- "$temporary_file"' EXIT

printf 'theme = %s\nwindow-theme = %s\n' "$theme" "$mode" > "$temporary_file"
mv -- "$temporary_file" "$ghostty_theme_file"
trap - EXIT

ghostty_has_owner="$(
  gdbus call \
    --session \
    --dest org.freedesktop.DBus \
    --object-path /org/freedesktop/DBus \
    --method org.freedesktop.DBus.NameHasOwner \
    com.mitchellh.ghostty 2>/dev/null || true
)"

if [[ "$ghostty_has_owner" == *"true"* ]]; then
  gdbus call \
    --session \
    --dest com.mitchellh.ghostty \
    --object-path /com/mitchellh/ghostty \
    --method org.gtk.Actions.Activate \
    reload-config '[]' '{}' >/dev/null 2>&1 || true
fi
