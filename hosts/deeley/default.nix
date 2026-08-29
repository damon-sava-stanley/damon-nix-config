{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/base.nix
    ../../modules/nixos/graphical.nix
    ../../modules/nixos/printing.nix
  ];

  networking.hostName = "deeley";

  services.fwupd.enable = true;

  # Recover the Framework touchpad when I2C HID stalls after suspend.
  powerManagement.resumeCommands = ''
    ${pkgs.kmod}/bin/modprobe -r i2c_hid_acpi
    ${pkgs.kmod}/bin/modprobe i2c_hid_acpi
  '';

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
