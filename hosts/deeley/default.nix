{ ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/base.nix
    ../../modules/nixos/graphical.nix
  ];

  networking.hostName = "deeley";

  users.users.damon = {
    isNormalUser = true;
    description = "Damon";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
  };

  # Keep this at the version used for the initial installation.
  system.stateVersion = "26.05";
}

