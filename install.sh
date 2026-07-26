#!/usr/bin/env bash

set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo_dir"

sudo cp -a flake.nix home hosts modules /etc/nixos/
sudo cp /etc/nixos/hardware-configuration.nix \
  /etc/nixos/hosts/deeley/hardware-configuration.nix
sudo nixos-rebuild build --flake /etc/nixos#deeley
sudo nixos-rebuild switch --flake /etc/nixos#deeley
