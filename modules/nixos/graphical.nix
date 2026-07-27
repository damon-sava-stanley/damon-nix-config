{ config, pkgs, ... }:

{
  # Niri is the Wayland compositor and registers a login session.
  programs.niri.enable = true;
  hardware.graphics.enable = true;

  services.geoclue2.enable = true;

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
    HandleLidSwitch = "suspend";
    HandleLidSwitchExternalPower = "suspend";
    HandleLidSwitchDocked = "ignore";
  };

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  # Chromium-family applications use their native Wayland backend.
  environment.sessionVariables.NIXOS_OZONE_WL = "1";
}
