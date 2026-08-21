#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ghostty_sync_script="${GHOSTTY_SYNC_SCRIPT:-$repository_root/home/damon/theme-sync/ghostty.sh}"
temporary_directory="$(mktemp -d)"
trap 'rm -rf -- "$temporary_directory"' EXIT

mkdir -p "$temporary_directory/bin" "$temporary_directory/cache"

printf '#!%s\n' "$BASH" > "$temporary_directory/bin/gdbus"
cat >> "$temporary_directory/bin/gdbus" <<'EOF'
printf '%s\n' "$*" >> "$GDBUS_CALL_LOG"
if [[ "$*" == *"NameHasOwner"* && "$GHOSTTY_TEST_HAS_OWNER" == true ]]; then
  printf '(true,)\n'
else
  printf '()\n'
fi
EOF
chmod +x "$temporary_directory/bin/gdbus"

export GDBUS_CALL_LOG="$temporary_directory/gdbus-calls"
export GHOSTTY_TEST_HAS_OWNER=true
export PATH="$temporary_directory/bin:$PATH"
export ghostty_theme_file="$temporary_directory/cache/theme.ghostty"

bash "$ghostty_sync_script" dark

cat > "$temporary_directory/expected-theme" <<'EOF'
theme = iTerm2 Solarized Dark
window-theme = dark
EOF

diff -u "$temporary_directory/expected-theme" "$ghostty_theme_file"
grep -Fq \
  'org.gtk.Actions.Activate reload-config [] {}' \
  "$GDBUS_CALL_LOG"

bash "$ghostty_sync_script" light

cat > "$temporary_directory/expected-theme" <<'EOF'
theme = iTerm2 Solarized Light
window-theme = light
EOF

diff -u "$temporary_directory/expected-theme" "$ghostty_theme_file"

: > "$GDBUS_CALL_LOG"
export GHOSTTY_TEST_HAS_OWNER=false
bash "$ghostty_sync_script" dark

grep -Fxq 'theme = iTerm2 Solarized Dark' "$ghostty_theme_file"
grep -Fxq 'window-theme = dark' "$ghostty_theme_file"
grep -Fq 'org.freedesktop.DBus.NameHasOwner' "$GDBUS_CALL_LOG"
if grep -Fq 'org.gtk.Actions.Activate' "$GDBUS_CALL_LOG"; then
  printf 'Ghostty reload unexpectedly activated an unowned bus name\n' >&2
  exit 1
fi
