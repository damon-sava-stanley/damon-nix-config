{ config, pkgs, ... }:

{
  # Niri is the Wayland compositor and registers a login session.
  programs.niri.enable = true;
  programs.steam.enable = true;
  hardware.graphics.enable = true;
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings.General.Experimental = true;
  };

  environment.systemPackages = [ pkgs.xwayland-satellite ];

  services.geoclue2.enable = true;
  services.automatic-timezoned.enable = true;

  # Niri cannot bind key releases yet. keyd exposes a real press/release layer
  # for the user-level hold-to-dictate listener instead.
  services.keyd = {
    enable = true;
    keyboards.dictation = {
      ids = [ "*" ];
      settings = {
        main.rightalt = "layer(dictate)";
        dictate = { };
      };
    };
  };
  users.groups.keyd = { };
  # keyd switches to this group before creating its IPC socket. Starting with
  # the group already selected avoids requiring CAP_SETGID in the hardened unit.
  systemd.services.keyd.serviceConfig.Group = "keyd";

  xdg.portal = {
    extraPortals = [ pkgs.darkman ];
    config.niri."org.freedesktop.impl.portal.Settings" = "darkman";
  };

  services.greetd = {
    enable = true;
    useTextGreeter = true;
    settings.default_session = {
      command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd ${config.programs.niri.package}/bin/niri-session";
      user = "greeter";
    };
  };

  security = {
    pam.services.swaylock = { };
    polkit.enable = true;
    rtkit.enable = true;
  };

  services.logind.settings.Login = {
    HandleLidSwitch = "suspend-then-hibernate";
    HandleLidSwitchExternalPower = "suspend-then-hibernate";
    HandleLidSwitchDocked = "ignore";
  };

  systemd.sleep.settings.Sleep.HibernateDelaySec = "2h";

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  # Chromium-family applications use their native Wayland backend.
  environment.sessionVariables.NIXOS_OZONE_WL = "1";
}
