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

export MOCK_FOCUSED_OUTPUT=DP-1
export MOCK_OUTPUTS_JSON='{
  "DP-1": {"current_mode": 0},
  "HDMI-A-1": {"current_mode": 1},
  "eDP-1": {"current_mode": 0}
}'
unset FAIL_FOCUSED_OUTPUT
run_helper
assert_commands $'output HDMI-A-1 off\noutput eDP-1 off'

export MOCK_OUTPUTS_JSON='{
  "DP-1": {"current_mode": 0},
  "HDMI-A-1": {"current_mode": null},
  "eDP-1": {"current_mode": null}
}'
export FAIL_FOCUSED_OUTPUT=true
run_helper
assert_commands $'output HDMI-A-1 on\noutput eDP-1 on'

printf 'niri monitor toggle tests passed\n'
