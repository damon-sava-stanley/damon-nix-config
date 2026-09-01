set -euo pipefail

trap 'dictate-control stop >/dev/null 2>&1 || true' EXIT

while IFS= read -r event; do
  case "$event" in
    +dictate)
      dictate-control start
      ;;
    -dictate)
      dictate-control stop
      ;;
  esac
done < <(keyd listen)
