#!/usr/bin/env bash
set -euo pipefail

script=${TOASTERS_SCRIPT:-home/damon/niri/flying-toasters.sh}
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
export XDG_RUNTIME_DIR="$test_dir"
export TOASTERS_LOG="$test_dir/log"
mkdir "$test_dir/bin"
printf '#!%s\n' "$(command -v bash)" > "$test_dir/bin/flying-toasters"
cat >> "$test_dir/bin/flying-toasters" <<'EOF'
set -euo pipefail
[[ "$SDL_VIDEODRIVER" == wayland ]]
[[ "$SDL_VIDEO_ALLOW_SCREENSAVER" == 0 ]]
[[ $# == 0 ]]
printf 'launch\n' >> "$TOASTERS_LOG"
if [[ ${HOLD:-0} == 1 ]]; then
  while [[ ! -f "$XDG_RUNTIME_DIR/release" ]]; do sleep 0.02; done
fi
exit "${RESULT:-0}"
EOF
chmod +x "$test_dir/bin/flying-toasters"
export PATH="$test_dir/bin:$PATH"
# Override conflicting session-wide SDL settings.
export SDL_VIDEODRIVER=x11 SDL_VIDEO_ALLOW_SCREENSAVER=1
bash "$script"
[[ $(wc -l < "$TOASTERS_LOG") == 1 ]]

HOLD=1 bash "$script" &
first=$!
for ((i=0; i<100; i++)); do
  [[ $(wc -l < "$TOASTERS_LOG") == 2 ]] && break
  sleep 0.02
done
[[ $(wc -l < "$TOASTERS_LOG") == 2 ]]
bash "$script"
[[ $(wc -l < "$TOASTERS_LOG") == 2 ]]
touch "$test_dir/release"
wait "$first"

status=0
RESULT=7 bash "$script" || status=$?
[[ $status == 7 ]]
bash "$script"
[[ $(wc -l < "$TOASTERS_LOG") == 4 ]]

# A crashed animation must not leave a stale singleton lock behind.
rm "$test_dir/release"
HOLD=1 bash "$script" &
crashed=$!
for ((i=0; i<100; i++)); do
  [[ $(wc -l < "$TOASTERS_LOG") == 5 ]] && break
  sleep 0.02
done
[[ $(wc -l < "$TOASTERS_LOG") == 5 ]]
kill -KILL "$crashed"
wait "$crashed" 2>/dev/null || true
# The mock's short-lived sleep child may briefly inherit the lock descriptor.
sleep 0.05
bash "$script"
[[ $(wc -l < "$TOASTERS_LOG") == 6 ]]
printf 'Flying Toasters launcher tests passed\n'
