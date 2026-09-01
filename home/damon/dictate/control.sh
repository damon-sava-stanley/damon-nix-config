set -euo pipefail

: "${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR is not set}"
: "${DICTATE_BIN:?DICTATE_BIN is not set}"
: "${DICTATE_MODEL:?DICTATE_MODEL is not set}"

state_directory="$XDG_RUNTIME_DIR/dictate"
pid_file="$state_directory/dictate.pid"
log_file="$state_directory/dictate.log"
language="${DICTATE_LANGUAGE:-en}"

mkdir -p "$state_directory"

read_pid() {
  local pid

  [[ -r "$pid_file" ]] || return 1
  IFS= read -r pid < "$pid_file"
  [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
  printf '%s\n' "$pid"
}

process_matches() {
  local pid=$1
  local argument

  [[ -r "/proc/$pid/cmdline" ]] || return 1
  while IFS= read -r argument; do
    [[ "$argument" == "$DICTATE_BIN" ]] && return 0
  done < <(tr '\0' '\n' < "/proc/$pid/cmdline")
  return 1
}

running_pid() {
  local pid
  local process_state

  pid="$(read_pid)" || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  read -r _ _ process_state _ < "/proc/$pid/stat" || return 1
  [[ "$process_state" != Z ]] || return 1
  process_matches "$pid" || return 1
  printf '%s\n' "$pid"
}

clean_stale_state() {
  if [[ -e "$pid_file" ]] && ! running_pid >/dev/null; then
    rm -f "$pid_file"
  fi
}

notify() {
  if [[ -n "${DICTATE_NOTIFY_BIN:-}" ]]; then
    "$DICTATE_NOTIFY_BIN" --app-name dictate --expire-time 1200 "$@" >/dev/null 2>&1 || true
  fi
}

start_dictation() {
  local pid

  clean_stale_state
  if pid="$(running_pid)"; then
    printf 'dictate is already listening (pid %s)\n' "$pid"
    return
  fi

  nohup "$DICTATE_BIN" \
    --output type \
    --lang "$language" \
    --model "$DICTATE_MODEL" \
    >> "$log_file" 2>&1 &
  pid=$!
  printf '%s\n' "$pid" > "$pid_file"
  notify "Dictation" "Listening…"
  printf 'dictate started (pid %s)\n' "$pid"
}

stop_dictation() {
  local pid

  clean_stale_state
  if ! pid="$(running_pid)"; then
    printf 'dictate is stopped\n'
    return
  fi

  kill -TERM "$pid"
  rm -f "$pid_file"
  notify "Dictation" "Stopped"
  printf 'dictate stopped (pid %s)\n' "$pid"
}

status_dictation() {
  local pid

  clean_stale_state
  if pid="$(running_pid)"; then
    printf 'dictate is listening (pid %s; log %s)\n' "$pid" "$log_file"
  else
    printf 'dictate is stopped (log %s)\n' "$log_file"
  fi
}

case "${1:-status}" in
  start)
    start_dictation
    ;;
  stop)
    stop_dictation
    ;;
  status)
    status_dictation
    ;;
  *)
    printf 'usage: dictate-control {start|stop|status}\n' >&2
    exit 2
    ;;
esac
