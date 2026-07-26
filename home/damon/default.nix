{ pkgs, ... }:

{
  home = {
    username = "damon";
    homeDirectory = "/home/damon";
    packages = [ pkgs.xdg-utils ];

    # Keep this at the version used when Home Manager is first activated.
    stateVersion = "26.05";
  };

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };

  programs.ghostty = {
    enable = true;
    settings.font-size = 12;
  };

  programs.chromium = {
    enable = true;
    package = pkgs.brave;
  };

  programs.fuzzel = {
    enable = true;
    settings.main = {
      terminal = "ghostty";
      layer = "overlay";
    };
  };

  programs.swaylock = {
    enable = true;
    settings = {
      color = "1e1e2e";
      indicator-radius = 100;
      indicator-thickness = 8;
      show-failed-attempts = true;
    };
  };

  services.swayidle = {
    enable = true;

    events = {
      before-sleep = "${pkgs.swaylock}/bin/swaylock -f";
      after-resume = "${pkgs.niri}/bin/niri msg action power-on-monitors";
      lock = "${pkgs.swaylock}/bin/swaylock -f";
    };

    timeouts = [
      {
        timeout = 300;
        command = "${pkgs.swaylock}/bin/swaylock -f";
      }
      {
        timeout = 600;
        command = "${pkgs.niri}/bin/niri msg action power-off-monitors";
        resumeCommand = "${pkgs.niri}/bin/niri msg action power-on-monitors";
      }
      {
        timeout = 1800;
        command = "${pkgs.systemd}/bin/systemctl suspend";
      }
    ];
  };

  # A window manager does not provide its own graphical privilege prompt.
  services.polkit-gnome.enable = true;

  xdg = {
    enable = true;

    configFile."niri/config.kdl".source = ./niri/config.kdl;

    mimeApps = {
      enable = true;
      defaultApplications = {
        "text/html" = "brave-browser.desktop";
        "x-scheme-handler/http" = "brave-browser.desktop";
        "x-scheme-handler/https" = "brave-browser.desktop";
      };
    };
  };
}
