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
    cloudflareAccess = {
      teamDomain = "late-thunder-9219.cloudflareaccess.com";
      audience = "68d97452fec8a3717afe57ce54949614ed41ea5f5cad9c52b68c988404d255a9";
      publicHostname = "zettel.ss-damon.com";
    };
    enablePiChat = true;
    enableDesktopCapture = true;
  };

  programs.fish.enable = true;

  # Recover the Framework touchpad when I2C HID stalls after suspend.
  powerManagement.resumeCommands = ''
    ${pkgs.kmod}/bin/modprobe -r i2c_hid_acpi
    ${pkgs.kmod}/bin/modprobe i2c_hid_acpi
  '';

  # The external displays sometimes fail to return after S4 resume. Keep
  # suspend-then-hibernate in suspend while AC power is available.
  systemd.sleep.settings.Sleep.HibernateOnACPower = false;

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
