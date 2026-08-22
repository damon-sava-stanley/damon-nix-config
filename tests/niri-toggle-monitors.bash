#!/usr/bin/env bash

set -euo pipefail

: "${NIRI_TOGGLE_SCRIPT:?set NIRI_TOGGLE_SCRIPT to the helper script}"

test_directory="$(mktemp -d)"
trap 'rm -rf "$test_directory"' EXIT

command_log="$test_directory/niri-commands"

niri() {
  case "$*" in
    "msg --json outputs")
      printf '%s\n' "$MOCK_OUTPUTS_JSON"
      ;;
    "msg --json focused-output")
      if [[ "${FAIL_FOCUSED_OUTPUT:-false}" == true ]]; then
        return 99
      fi
      printf '{"name":"%s"}\n' "$MOCK_FOCUSED_OUTPUT"
      ;;
    "msg output "*)
      printf '%s\n' "${*:2}" >> "$MOCK_COMMAND_LOG"
      ;;
    *)
      printf 'unexpected niri invocation: %s\n' "$*" >&2
      return 98
      ;;
  esac
}
export -f niri

run_helper() {
  : > "$command_log"
  MOCK_COMMAND_LOG="$command_log" \
    XDG_RUNTIME_DIR="$test_directory" \
    bash "$NIRI_TOGGLE_SCRIPT"
}

assert_commands() {
  local expected=$1
  local actual
  actual="$(cat "$command_log")"

  if [[ "$actual" != "$expected" ]]; then
    printf 'expected commands:\n%s\nactual commands:\n%s\n' "$expected" "$actual" >&2
    exit 1
  fi
}

state_file="$test_directory/niri-toggle-monitors.state"

export MOCK_FOCUSED_OUTPUT=DP-4
export MOCK_OUTPUTS_JSON='{
  "DP-4": {"current_mode": 0},
  "DP-6": {"current_mode": 1},
  "eDP-1": {"current_mode": null}
}'
unset FAIL_FOCUSED_OUTPUT
run_helper
assert_commands 'output DP-6 off'

if [[ "$(cat "$state_file")" != DP-6 ]]; then
  printf 'expected saved output DP-6\n' >&2
  exit 1
fi

export MOCK_OUTPUTS_JSON='{
  "DP-4": {"current_mode": 0},
  "eDP-1": {"current_mode": null}
}'
export FAIL_FOCUSED_OUTPUT=true
run_helper
assert_commands 'output DP-6 on'

if [[ -e "$state_file" ]]; then
  printf 'expected monitor toggle state to be cleared\n' >&2
  exit 1
fi

printf 'niri monitor toggle tests passed\n'
