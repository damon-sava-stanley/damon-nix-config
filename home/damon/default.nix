{ pkgs, unstablePkgs, ... }:

{
  home = {
    username = "damon";
    homeDirectory = "/home/damon";
    packages = [
      unstablePkgs.codex
      pkgs.dropbox
      pkgs.gh
      pkgs.xdg-utils
    ];

    # Keep this at the version used when Home Manager is first activated.
    stateVersion = "26.05";
  };

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };

  programs.git = {
    enable = true;
    settings.user = {
      name = "Damon Sava Stanley";
      email = "damonsava@gmail.com";
    };
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

  programs.waybar = {
    enable = true;
    systemd.enable = true;

    settings.mainBar = {
      layer = "top";
      position = "top";
      height = 30;

      modules-left = [ "niri/workspaces" ];
      modules-center = [ "niri/window" ];
      modules-right = [
        "tray"
        "network"
        "wireplumber"
        "backlight"
        "battery"
        "clock"
      ];

      "niri/workspaces" = {
        format = "{icon}";
        format-icons = {
          active = "●";
          default = "○";
          urgent = "!";
        };
      };

      "niri/window" = {
        format = "{title}";
        separate-outputs = true;
      };

      network = {
        format-wifi = "{essid}";
        format-ethernet = "wired";
        format-disconnected = "offline";
      };

      wireplumber.format = "{volume}%";
      backlight.format = "{percent}%";
      battery.format = "{capacity}%";
      clock.format = "{:%a %b %d  %H:%M}";
      tray.spacing = 10;
    };

    style = ''
      * {
        font-family: sans-serif;
        font-size: 13px;
      }

      window#waybar {
        background: #1e1e2e;
        color: #cdd6f4;
      }

      #workspaces button {
        padding: 0 7px;
        color: #6c7086;
      }

      #workspaces button.active {
        color: #89b4fa;
      }

      #window, #tray, #network, #wireplumber,
      #backlight, #battery, #clock {
        padding: 0 8px;
      }
    '';
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
