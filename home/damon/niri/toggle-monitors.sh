set -euo pipefail

outputs_json="$(niri msg --json outputs)"

if jq --exit-status 'any(.[]; .current_mode == null)' \
  <<< "$outputs_json" >/dev/null; then
  jq --raw-output '
    to_entries[]
    | select(.value.current_mode == null)
    | .key
  ' <<< "$outputs_json" |
    while IFS= read -r output; do
      niri msg output "$output" on
    done
  exit 0
fi

focused_output="$(
  niri msg --json focused-output |
    jq --exit-status --raw-output '.name'
)"

jq --raw-output --arg focused "$focused_output" '
  to_entries[]
  | select(.key != $focused)
  | .key
' <<< "$outputs_json" |
  while IFS= read -r output; do
    niri msg output "$output" off
  done
