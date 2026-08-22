set -euo pipefail

state_file="${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR is not set}/niri-toggle-monitors.state"

if [[ -s "$state_file" ]]; then
  while IFS= read -r output; do
    if [[ -n "$output" ]]; then
      niri msg output "$output" on
    fi
  done < "$state_file"
  rm -- "$state_file"
  exit 0
fi

rm -f -- "$state_file"

outputs_json="$(niri msg --json outputs)"
focused_output="$(
  niri msg --json focused-output |
    jq --exit-status --raw-output '.name'
)"

umask 077
state_tmp="$(mktemp "${state_file}.XXXXXX")"
trap 'rm -f -- "$state_tmp"' EXIT

jq --raw-output --arg focused "$focused_output" '
  to_entries[]
  | select(.key != $focused and .value.current_mode != null)
  | .key
' <<< "$outputs_json" > "$state_tmp"

if [[ ! -s "$state_tmp" ]]; then
  exit 0
fi

mv -- "$state_tmp" "$state_file"
trap - EXIT

while IFS= read -r output; do
  if [[ -n "$output" ]]; then
    niri msg output "$output" off
  fi
done < "$state_file"
