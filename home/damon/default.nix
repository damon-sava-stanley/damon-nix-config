{
  config,
  pkgs,
  unstablePkgs,
  ...
}:

let
  waybarThemeFile = "${config.xdg.cacheHome}/waybar/solarized.css";
  niriThemeFile = "${config.xdg.cacheHome}/niri/solarized.kdl";
  solarizedDarkWallpaper = "${pkgs.nixos-artwork.wallpapers.nineish-solarized-dark}/share/backgrounds/nixos/nix-wallpaper-nineish-solarized-dark.png";
  solarizedLightWallpaper = "${pkgs.nixos-artwork.wallpapers.nineish-solarized-light}/share/backgrounds/nixos/nix-wallpaper-nineish-solarized-light.png";

  waybarThemeWatcher = pkgs.writeShellApplication {
    name = "waybar-theme-watcher";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.glib
      pkgs.procps
      pkgs.awww
    ];
    text = ''
      waybar_theme_file=${waybarThemeFile}
      niri_theme_file=${niriThemeFile}

      set_wallpaper() {
        wallpaper=$1

        # The daemon and watcher start together with the graphical session.
        # Give the daemon a moment to create its socket on initial login.
        for _ in {1..20}; do
          if awww query >/dev/null 2>&1; then
            awww img \
              --resize crop \
              --transition-type fade \
              --transition-duration 1 \
              "$wallpaper"
            return
          fi
          sleep 0.1
        done
      }

      apply_theme() {
        portal_value="$(
          gdbus call \
            --session \
            --dest org.freedesktop.portal.Desktop \
            --object-path /org/freedesktop/portal/desktop \
            --method org.freedesktop.portal.Settings.Read \
            org.freedesktop.appearance \
            color-scheme 2>/dev/null || true
        )"

        mkdir -p \
          "$(dirname "$waybar_theme_file")" \
          "$(dirname "$niri_theme_file")"
        waybar_temporary_file="$waybar_theme_file.tmp.$$"
        niri_temporary_file="$niri_theme_file.tmp.$$"

        if [[ "$portal_value" == *"uint32 1"* ]]; then
          wallpaper=${solarizedDarkWallpaper}
          cat > "$waybar_temporary_file" <<'EOF'
      @define-color bar_background #002b36;
      @define-color bar_foreground #839496;
      @define-color workspace_foreground #586e75;
      @define-color active_workspace #268bd2;
      @define-color battery_charging #859900;
      @define-color battery_low #dc322f;
      EOF
          cat > "$niri_temporary_file" <<'EOF'
      layout {
          background-color "#002b36"

          focus-ring {
              active-color "#268bd2"
              inactive-color "#586e75"
              urgent-color "#dc322f"
          }
      }

      overview {
          backdrop-color "#002b36"
      }
      EOF
        else
          wallpaper=${solarizedLightWallpaper}
          cat > "$waybar_temporary_file" <<'EOF'
      @define-color bar_background #fdf6e3;
      @define-color bar_foreground #657b83;
      @define-color workspace_foreground #93a1a1;
      @define-color active_workspace #268bd2;
      @define-color battery_charging #859900;
      @define-color battery_low #dc322f;
      EOF
          cat > "$niri_temporary_file" <<'EOF'
      layout {
          background-color "#fdf6e3"

          focus-ring {
              active-color "#268bd2"
              inactive-color "#93a1a1"
              urgent-color "#dc322f"
          }
      }

      overview {
          backdrop-color "#fdf6e3"
      }
      EOF
        fi

        mv "$waybar_temporary_file" "$waybar_theme_file"
        mv "$niri_temporary_file" "$niri_theme_file"
        pkill -x -USR2 waybar || true
        set_wallpaper "$wallpaper"
      }

      apply_theme

      if [[ "''${1:-}" == "--once" ]]; then
        exit 0
      fi

      while true; do
        while IFS= read -r event; do
          if [[ "$event" == *"org.freedesktop.appearance"*"color-scheme"* ]]; then
            apply_theme
          fi
        done < <(
          gdbus monitor \
            --session \
            --dest org.freedesktop.portal.Desktop \
            --object-path /org/freedesktop/portal/desktop 2>/dev/null || true
        )
        sleep 1
      done
    '';
  };
in
{
  home = {
    username = "damon";
    homeDirectory = "/home/damon";
    sessionVariables = {
      EDITOR = "nvim";
      VISUAL = "nvim";
    };
    packages = [
      # Haskell toolchain; Cabal manages project dependencies.
      pkgs.cabal-install
      pkgs.brightnessctl
      pkgs.fd
      pkgs.ghc
      pkgs.haskell-language-server
      pkgs.keepassxc
      pkgs.lsof
      pkgs.networkmanager_dmenu
      pkgs.networkmanagerapplet
      pkgs.playerctl
      pkgs.pwvucontrol
      pkgs.python314
      pkgs.ripgrep
      pkgs.uv
      unstablePkgs.codex
      pkgs.dropbox
      pkgs.gh
      pkgs.xdg-utils
    ];

    # Keep this at the version used when Home Manager is first activated.
    stateVersion = "26.05";
  };

  programs.tmux.enable = true;

  programs.neovim = {
    enable = true;
    defaultEditor = false;
    viAlias = true;
    vimAlias = true;

    plugins = [
      # Sidekick's Copilot integration is optional; omit its unfree language
      # server because only the Codex CLI integration is enabled below.
      (pkgs.vimPlugins.sidekick-nvim.overrideAttrs (_: {
        runtimeDeps = [ ];
      }))
      pkgs.vimPlugins.nvim-lspconfig
      pkgs.vimPlugins.plenary-nvim
      pkgs.vimPlugins.telescope-nvim
    ];

    initLua = ''
      vim.g.mapleader = " "
      vim.g.maplocalleader = " "

      vim.opt.autoread = true

      vim.lsp.enable("hls")

      require("telescope").setup({})

      local telescope = require("telescope.builtin")
      vim.keymap.set("n", "<leader>ff", telescope.find_files,
        { desc = "Find files" })
      vim.keymap.set("n", "<leader>fb", telescope.buffers,
        { desc = "Find buffers" })
      vim.keymap.set("n", "<leader>fg", telescope.live_grep,
        { desc = "Find text" })
      vim.keymap.set("n", "<leader>fr", telescope.oldfiles,
        { desc = "Find recent files" })

      require("sidekick").setup({
        nes = {
          enabled = false,
        },
        cli = {
          mux = {
            enabled = true,
            backend = "tmux",
            create = "window",
          },
          picker = "telescope",
        },
      })

      local sidekick_cli = require("sidekick.cli")
      vim.keymap.set("n", "<leader>cc", function()
        sidekick_cli.toggle({ name = "codex", focus = true })
      end, { desc = "Toggle Codex" })
      vim.keymap.set("n", "<leader>ca", function()
        sidekick_cli.select({ filter = { installed = true } })
      end, { desc = "Attach to AI CLI" })
      vim.keymap.set("x", "<leader>cs", function()
        sidekick_cli.send({ msg = "{selection}" })
      end, { desc = "Send selection to Codex" })
      vim.keymap.set("n", "<leader>cf", function()
        sidekick_cli.send({ msg = "{file}" })
      end, { desc = "Send file to Codex" })
      vim.keymap.set("n", "<leader>cd", function()
        sidekick_cli.send({
          msg = "Please help fix the diagnostics in {file}:\n{diagnostics}",
        })
      end, { desc = "Send diagnostics to Codex" })
      vim.keymap.set({ "n", "x" }, "<leader>cp", function()
        sidekick_cli.prompt()
      end, { desc = "Select Codex prompt" })

      vim.api.nvim_create_autocmd(
        { "FocusGained", "BufEnter", "CursorHold" },
        { command = "checktime" }
      )
    '';
  };

  programs.git = {
    enable = true;
    lfs.enable = true;
    settings.init.defaultBranch = "main";
    settings.push.autoSetupRemote = true;
    settings.user = {
      name = "Damon Sava Stanley";
      email = "damonsava@gmail.com";
    };
  };

  programs.ghostty = {
    enable = true;
    settings = {
      font-size = 12;
      theme = "light:iTerm2 Solarized Light,dark:iTerm2 Solarized Dark";
    };
  };

  services.darkman = {
    enable = true;
    settings = {
      portal = true;
      usegeoclue = true;
    };
  };

  programs.chromium = {
    enable = true;
    package = pkgs.brave;
    extensions = [
      {
        # Dark Reader
        id = "eimadpbcbfnmbkopoojfekhnkhdbieeh";
      }
    ];
  };

  programs.fuzzel = {
    enable = true;
    settings.main = {
      terminal = "ghostty -e";
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
        "memory"
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
        on-click = "${pkgs.networkmanager_dmenu}/bin/networkmanager_dmenu";
      };

      wireplumber = {
        format = "🔊 {volume}%";
        format-muted = "🔇 muted";
        on-click = "pwvucontrol";
      };
      memory.format = "🧠 {percentage}%";
      backlight.format = "☀️ {percent}%";
      battery = {
        format = "🔋 {capacity}%";
        format-charging = "🔋⚡ {capacity}%";
        states.warning = 19;
      };
      clock = {
        format = "{:%a %b %d  %H:%M}";
        on-click = "${pkgs.brave}/bin/brave https://calendar.google.com";
      };
      tray.spacing = 10;
    };

    style = ''
      @import url("${waybarThemeFile}");

      * {
        font-family: monospace;
        font-size: 14px;
        font-weight: 500;
      }

      window#waybar {
        background: @bar_background;
        color: @bar_foreground;
      }

      #workspaces button {
        padding: 0 7px;
        color: @workspace_foreground;
      }

      #workspaces button.active {
        color: @active_workspace;
      }

      #window, #tray, #network, #wireplumber,
      #memory, #backlight, #battery, #clock {
        padding: 0 8px;
      }

      #battery.charging {
        color: @battery_charging;
      }

      #battery.warning:not(.charging) {
        color: @battery_low;
      }
    '';
  };

  xdg.configFile."networkmanager-dmenu/config.ini".text = ''
    [dmenu]
    dmenu_command = fuzzel

    [editor]
    gui = ${pkgs.networkmanagerapplet}/bin/nm-connection-editor
  '';

  systemd.user.services.waybar-theme-watcher = {
    Unit = {
      Description = "Keep Waybar, Niri, and the wallpaper in sync with the system color scheme";
      PartOf = [ config.wayland.systemd.target ];
      Wants = [ "awww-daemon.service" ];
      After = [ "awww-daemon.service" ];
      Before = [ "waybar.service" ];
    };

    Service = {
      ExecStartPre = "${waybarThemeWatcher}/bin/waybar-theme-watcher --once";
      ExecStart = "${waybarThemeWatcher}/bin/waybar-theme-watcher";
      Restart = "always";
      RestartSec = 1;
    };

    Install.WantedBy = [ config.wayland.systemd.target ];
  };

  systemd.user.services.awww-daemon = {
    Unit = {
      Description = "Wayland wallpaper daemon";
      PartOf = [ config.wayland.systemd.target ];
    };

    Service = {
      ExecStart = "${pkgs.awww}/bin/awww-daemon";
      Restart = "on-failure";
    };

    Install.WantedBy = [ config.wayland.systemd.target ];
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
