#!/usr/bin/env bash

set -euo pipefail

: "${DICTATE_LISTENER_SCRIPT:?set DICTATE_LISTENER_SCRIPT to the listener script}"
: "${TEST_BASH:?set TEST_BASH to bash}"

test_directory="$(mktemp -d)"
trap 'rm -rf "$test_directory"' EXIT
mock_bin="$test_directory/bin"
command_log="$test_directory/commands"
mkdir -p "$mock_bin"

printf '#!%s\n' "$TEST_BASH" > "$mock_bin/keyd"
cat >> "$mock_bin/keyd" <<'EOF'
set -euo pipefail
[[ "${1:-}" == listen ]]
printf '%s\n' +unrelated +dictate -dictate
EOF

printf '#!%s\n' "$TEST_BASH" > "$mock_bin/dictate-control"
cat >> "$mock_bin/dictate-control" <<'EOF'
set -euo pipefail
printf '%s\n' "$1" >> "$MOCK_COMMAND_LOG"
EOF
chmod +x "$mock_bin/keyd" "$mock_bin/dictate-control"

MOCK_COMMAND_LOG="$command_log" \
  PATH="$mock_bin:$PATH" \
  bash "$DICTATE_LISTENER_SCRIPT"

# The final stop comes from the listener's EXIT trap. It prevents a lost keyd
# connection or a service restart from leaving the microphone active.
expected=$'start\nstop\nstop'
actual="$(cat "$command_log")"
if [[ "$actual" != "$expected" ]]; then
  printf 'expected listener commands:\n%s\nactual commands:\n%s\n' "$expected" "$actual" >&2
  exit 1
fi

printf 'dictate key listener tests passed\n'
