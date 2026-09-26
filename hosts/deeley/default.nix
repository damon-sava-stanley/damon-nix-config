{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/base.nix
    ../../modules/nixos/cloudflared.nix
    ../../modules/nixos/graphical.nix
    ../../modules/nixos/printing.nix
  ];

  networking.hostName = "deeley";

  services.fwupd.enable = true;

  services.remote-zettel = {
    enable = true;
    dataRoot = "/home/damon/Dropbox/000_zettelkasten";
    dataOwner = "damon";
  };

  programs.fish.enable = true;

  # Recover the Framework touchpad when I2C HID stalls after suspend.
  powerManagement.resumeCommands = ''
    ${pkgs.kmod}/bin/modprobe -r i2c_hid_acpi
    ${pkgs.kmod}/bin/modprobe i2c_hid_acpi
  '';

  users.users.damon = {
    isNormalUser = true;
    description = "Damon";
    shell = pkgs.fish;
    extraGroups = [
      "dialout"
      "networkmanager"
      "keyd"
      "wheel"
    ];
  };

  # Keep this at the version used for the initial installation.
  system.stateVersion = "26.05";
}
