#!/usr/bin/env bash

set -euo pipefail

: "${DICTATE_CONTROL_SCRIPT:?set DICTATE_CONTROL_SCRIPT to the helper script}"
: "${TEST_BASH:?set TEST_BASH to bash}"

test_directory="$(mktemp -d)"
trap 'if [[ -r "$test_directory/runtime/dictate/dictate.pid" ]]; then kill "$(cat "$test_directory/runtime/dictate/dictate.pid")" 2>/dev/null || true; fi; rm -rf "$test_directory"' EXIT

mock_dictate="$test_directory/mock-dictate"
invocation_log="$test_directory/invocations"
model="$test_directory/ggml-model.bin"

printf '#!%s\n' "$TEST_BASH" > "$mock_dictate"
cat >> "$mock_dictate" <<'EOF'
set -euo pipefail
printf '%s\n' "$*" >> "$MOCK_INVOCATION_LOG"
trap 'exit 0' TERM INT
while true; do
  sleep 0.01
done
EOF
chmod +x "$mock_dictate"
touch "$model"
mkdir -p "$test_directory/runtime"

run_control() {
  DICTATE_BIN="$mock_dictate" \
    DICTATE_MODEL="$model" \
    DICTATE_NOTIFY_BIN="" \
    MOCK_INVOCATION_LOG="$invocation_log" \
    XDG_RUNTIME_DIR="$test_directory/runtime" \
    bash "$DICTATE_CONTROL_SCRIPT" "$@"
}

wait_for_invocation() {
  for _ in {1..50}; do
    [[ -s "$invocation_log" ]] && return
    sleep 0.01
  done
  echo "mock dictate was not invoked" >&2
  exit 1
}

process_is_running() {
  local pid=$1
  local process_id process_name process_state process_rest

  kill -0 "$pid" 2>/dev/null || return 1
  read -r process_id process_name process_state process_rest < "/proc/$pid/stat" || return 1
  [[ "$process_state" != Z ]]
}

run_control start >/dev/null
wait_for_invocation
pid_file="$test_directory/runtime/dictate/dictate.pid"
first_pid="$(cat "$pid_file")"
kill -0 "$first_pid"

expected_args="--output type --lang en --model $model"
if [[ "$(cat "$invocation_log")" != "$expected_args" ]]; then
  printf 'unexpected dictate arguments: %s\n' "$(cat "$invocation_log")" >&2
  exit 1
fi

run_control start >/dev/null
if [[ "$(wc -l < "$invocation_log")" -ne 1 ]]; then
  echo "a repeated press started a second dictate process" >&2
  exit 1
fi

run_control stop >/dev/null
if [[ -e "$pid_file" ]]; then
  echo "stop left the pid file behind" >&2
  exit 1
fi

for _ in {1..50}; do
  ! process_is_running "$first_pid" && break
  sleep 0.01
done
if process_is_running "$first_pid"; then
  echo "stop left dictate running" >&2
  exit 1
fi

run_control stop >/dev/null

sleep 30 &
unrelated_pid=$!
printf '%s\n' "$unrelated_pid" > "$pid_file"
run_control stop >/dev/null
kill -0 "$unrelated_pid"
kill "$unrelated_pid"
wait "$unrelated_pid" 2>/dev/null || true

printf 'dictate controller tests passed\n'
