{
  config,
  pkgs,
  unstablePkgs,
  ...
}:

let
  waybarThemeFile = "${config.xdg.cacheHome}/waybar/solarized.css";

  waybarThemeWatcher = pkgs.writeShellApplication {
    name = "waybar-theme-watcher";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.glib
      pkgs.procps
    ];
    text = ''
      theme_file=${waybarThemeFile}

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

        mkdir -p "$(dirname "$theme_file")"
        temporary_file="$theme_file.tmp.$$"

        if [[ "$portal_value" == *"uint32 1"* ]]; then
          cat > "$temporary_file" <<'EOF'
      @define-color bar_background #002b36;
      @define-color bar_foreground #839496;
      @define-color workspace_foreground #586e75;
      @define-color active_workspace #268bd2;
      @define-color battery_charging #859900;
      @define-color battery_low #dc322f;
      EOF
        else
          cat > "$temporary_file" <<'EOF'
      @define-color bar_background #fdf6e3;
      @define-color bar_foreground #657b83;
      @define-color workspace_foreground #93a1a1;
      @define-color active_workspace #268bd2;
      @define-color battery_charging #859900;
      @define-color battery_low #dc322f;
      EOF
        fi

        mv "$temporary_file" "$theme_file"
        pkill -x -USR2 waybar || true
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
      EDITOR = "ghostty -e nvim";
      VISUAL = "ghostty -e nvim";
    };
    packages = [
      # Haskell toolchain; Cabal manages project dependencies.
      pkgs.cabal-install
      pkgs.brightnessctl
      pkgs.fd
      pkgs.ghc
      pkgs.haskell-language-server
      pkgs.lsof
      pkgs.playerctl
      pkgs.ripgrep
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
      };

      wireplumber = {
        format = "🔊 {volume}%";
        format-muted = "🔇 muted";
      };
      memory.format = "🧠 {percentage}%";
      backlight.format = "☀️ {percent}%";
      battery = {
        format = "🔋 {capacity}%";
        format-charging = "🔋⚡ {capacity}%";
        states.warning = 19;
      };
      clock.format = "{:%a %b %d  %H:%M}";
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

  systemd.user.services.waybar-theme-watcher = {
    Unit = {
      Description = "Keep Waybar colors in sync with the system color scheme";
      PartOf = [ config.wayland.systemd.target ];
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
