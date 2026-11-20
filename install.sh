#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo_dir"
if [[ $# -gt 1 || ( $# -eq 1 && $1 != --check ) ]]; then
  echo 'Usage: ./install.sh [--check]' >&2
  exit 2
fi

# Retain the built closure until activation finishes, and activate these exact bytes.
build_dir="$(mktemp -d -t deeley-install.XXXXXXXX)"
trap 'rm -rf -- "$build_dir"' EXIT
nix build --no-write-lock-file --out-link "$build_dir/system" \
  "path:$repo_dir#nixosConfigurations.deeley.config.system.build.toplevel"
target="$(readlink -f -- "$build_dir/system")"
python3 "$repo_dir/scripts/check-host-update.py" "$target"
if [[ ${1:-} == --check ]]; then
  echo "Update preflight passed: $target"
  exit 0
fi
sudo nixos-rebuild switch --store-path "$target"
