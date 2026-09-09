{
  config,
  dictate-src,
  pkgs,
  unstablePkgs,
  ...
}:

let
  waybarThemeFile = "${config.xdg.cacheHome}/waybar/solarized.css";
  niriThemeFile = "${config.xdg.cacheHome}/niri/solarized.kdl";
  fuzzelThemeFile = "${config.xdg.cacheHome}/theme-sync/fuzzel.ini";
  neovimThemeFile = "${config.xdg.cacheHome}/theme-sync/neovim";
  ghosttyThemeFile = "${config.xdg.cacheHome}/theme-sync/ghostty.conf";
  solarizedDarkWallpaper = "${pkgs.nixos-artwork.wallpapers.nineish-solarized-dark}/share/backgrounds/nixos/nix-wallpaper-nineish-solarized-dark.png";
  solarizedLightWallpaper = "${pkgs.nixos-artwork.wallpapers.nineish-solarized-light}/share/backgrounds/nixos/nix-wallpaper-nineish-solarized-light.png";

  betterBibtexVersion = "9.0.27";
  betterBibtex = pkgs.fetchurl {
    url = "https://github.com/retorquere/zotero-better-bibtex/releases/download/v${betterBibtexVersion}/zotero-better-bibtex-${betterBibtexVersion}.xpi";
    hash = "sha256-r6W6hbIYd8mZrYklTNIAp76js5XpEPI3mGZU6ryzxys=";
  };
  zoteroWithBetterBibtex =
    pkgs.runCommand "${pkgs.zotero.name}-with-better-bibtex-${betterBibtexVersion}"
      {
        meta = pkgs.zotero.meta;
      }
      ''
        cp -a ${pkgs.zotero} "$out"
        chmod u+w "$out" "$out/lib" "$out/lib/distribution"
        install -Dm444 ${betterBibtex} \
          "$out/lib/distribution/extensions/better-bibtex@iris-advies.com.xpi"
      '';

  niriToggleMonitors = pkgs.writeShellApplication {
    name = "niri-toggle-monitors";
    runtimeInputs = [
      pkgs.jq
      pkgs.niri
    ];
    text = builtins.readFile ./niri/toggle-monitors.sh;
  };

  whisperCpp = pkgs.whisper-cpp.override {
    vulkanSupport = true;
  };

  dictateModel = pkgs.fetchurl {
    name = "ggml-large-v3-turbo-q5_0.bin";
    url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/98aa99a0a9db05ae2342309f5096248665f7cba3/ggml-large-v3-turbo-q5_0.bin";
    hash = "sha256-OUIhcJzVrR9AxG5gMcphvOiJMebgiMGIKUxtWlX/p+I=";
  };

  dictate = pkgs.buildGoModule {
    pname = "dictate";
    version = "0-unstable-2026-03-14";
    src = dictate-src;
    vendorHash = "sha256-Y6/dBYyG252dmyVhcmN+25lqD4E0e9Vm5x8aFYC7J/I=";
    subPackages = [ "cmd/dictate" ];

    nativeBuildInputs = [ pkgs.makeWrapper ];

    postInstall = ''
      ln -s ${whisperCpp}/bin/whisper-stream "$out/bin/whisper-stream"
    '';

    postFixup = ''
      wrapProgram "$out/bin/dictate" \
        --prefix PATH : ${
          pkgs.lib.makeBinPath [
            pkgs.pipewire
            pkgs.wtype
          ]
        }
    '';

    meta = {
      description = "Local streaming speech-to-text for focused Wayland inputs";
      homepage = "https://github.com/msf/dictate";
      license = pkgs.lib.licenses.gpl2Only;
      mainProgram = "dictate";
      platforms = pkgs.lib.platforms.linux;
    };
  };

  dictateControl = pkgs.writeShellApplication {
    name = "dictate-control";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.libnotify
    ];
    text = ''
      DICTATE_BIN=${dictate}/bin/dictate
      DICTATE_MODEL=${dictateModel}
      DICTATE_NOTIFY_BIN=${pkgs.libnotify}/bin/notify-send
      export DICTATE_BIN DICTATE_MODEL DICTATE_NOTIFY_BIN
      ${builtins.readFile ./dictate/control.sh}
    '';
  };

  dictateKeyListener = pkgs.writeShellApplication {
    name = "dictate-key-listener";
    runtimeInputs = [
      dictateControl
      pkgs.keyd
    ];
    text = builtins.readFile ./dictate/listen.sh;
  };

  ghosttyThemeSync = pkgs.writeShellApplication {
    name = "ghostty-theme-sync";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.glib
    ];
    text = ''
      ghostty_theme_file=${ghosttyThemeFile}
      export ghostty_theme_file
      ${builtins.readFile ./theme-sync/ghostty.sh}
    '';
  };

  waybarThemeWatcher = pkgs.writeShellApplication {
    name = "waybar-theme-watcher";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.darkman
      pkgs.glib
      pkgs.procps
      pkgs.systemd
      pkgs.awww
    ];
    text = ''
      waybar_theme_file=${waybarThemeFile}
      niri_theme_file=${niriThemeFile}
      fuzzel_theme_file=${fuzzelThemeFile}
      neovim_theme_file=${neovimThemeFile}

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

      read_portal_mode() {
        portal_value="$(
          gdbus call \
            --session \
            --dest org.freedesktop.portal.Desktop \
            --object-path /org/freedesktop/portal/desktop \
            --method org.freedesktop.portal.Settings.Read \
            org.freedesktop.appearance \
            color-scheme 2>/dev/null || true
        )"

        if [[ "$portal_value" == *"uint32 1"* ]]; then
          echo dark
        elif [[ "$portal_value" == *"uint32 2"* ]]; then
          echo light
        else
          echo unknown
        fi
      }

      repair_portal() {
        mode=$1

        # Darkman is the source of truth. Give xdg-desktop-portal time to
        # relay the change, then recover it if its cached value is stale.
        for _ in {1..10}; do
          if [[ "$(read_portal_mode)" == "$mode" ]]; then
            return
          fi
          sleep 0.1
        done

        echo "Restarting xdg-desktop-portal: its color scheme is stale" >&2
        systemctl --user restart xdg-desktop-portal.service || true
      }

      apply_theme() {
        mode=$1

        mkdir -p \
          "$(dirname "$waybar_theme_file")" \
          "$(dirname "$niri_theme_file")" \
          "$(dirname "$fuzzel_theme_file")" \
          "$(dirname "$neovim_theme_file")"
        waybar_temporary_file="$waybar_theme_file.tmp.$$"
        niri_temporary_file="$niri_theme_file.tmp.$$"
        fuzzel_temporary_file="$fuzzel_theme_file.tmp.$$"
        neovim_temporary_file="$neovim_theme_file.tmp.$$"

        if [[ "$mode" == dark ]]; then
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
          cat > "$fuzzel_temporary_file" <<'EOF'
      [colors]
      background=002b36ff
      text=839496ff
      message=839496ff
      prompt=93a1a1ff
      placeholder=586e75ff
      input=839496ff
      match=cb4b16ff
      selection=073642ff
      selection-text=93a1a1ff
      selection-match=cb4b16ff
      counter=586e75ff
      border=fdf6e3ff
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
          cat > "$fuzzel_temporary_file" <<'EOF'
      [colors]
      background=fdf6e3ff
      text=657b83ff
      message=657b83ff
      prompt=586e75ff
      placeholder=93a1a1ff
      input=657b83ff
      match=cb4b16ff
      selection=eee8d5ff
      selection-text=586e75ff
      selection-match=cb4b16ff
      counter=93a1a1ff
      border=002b36ff
      EOF
        fi

        printf '%s\n' "$mode" > "$neovim_temporary_file"
        mv "$waybar_temporary_file" "$waybar_theme_file"
        mv "$niri_temporary_file" "$niri_theme_file"
        mv "$fuzzel_temporary_file" "$fuzzel_theme_file"
        mv "$neovim_temporary_file" "$neovim_theme_file"
        ${ghosttyThemeSync}/bin/ghostty-theme-sync "$mode"
        systemctl --user --no-block try-restart waybar.service || true
        pkill -x -USR1 nvim || true
        set_wallpaper "$wallpaper"
      }

      mode="$(darkman get 2>/dev/null || true)"
      if [[ "$mode" != dark && "$mode" != light ]]; then
        mode="$(read_portal_mode)"
      fi
      if [[ "$mode" != dark && "$mode" != light ]]; then
        mode=light
      fi
      apply_theme "$mode"

      if [[ "''${1:-}" == "--once" ]]; then
        exit 0
      fi

      while true; do
        while IFS= read -r mode; do
          if [[ "$mode" == dark || "$mode" == light ]]; then
            apply_theme "$mode"
            repair_portal "$mode"
          fi
        done < <(
          darkman watch 2>/dev/null || true
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
      pkgs.bottom
      pkgs.darktable
      pkgs.exiftool
      pkgs.fd
      pkgs.gimp3
      pkgs.ghc
      pkgs.haskell-language-server
      pkgs.keepassxc
      pkgs.lsof
      pkgs.marksman
      dictate
      dictateControl
      niriToggleMonitors
      pkgs.networkmanager_dmenu
      pkgs.networkmanagerapplet
      pkgs.nodejs
      pkgs.pandoc
      pkgs.playerctl
      pkgs.pwvucontrol
      pkgs.python314
      pkgs.rapid-photo-downloader
      pkgs.ripgrep
      pkgs.texliveSmall
      pkgs.unzip
      pkgs.uv
      pkgs.wev
      zoteroWithBetterBibtex
      unstablePkgs.codex
      pkgs.dropbox
      pkgs.gh
      pkgs.xdg-utils
      pkgs.zmk-studio
    ];

    file.".agents/skills" = {
      source = ./codex-skills;
    };

    # Keep this at the version used when Home Manager is first activated.
    stateVersion = "26.05";
  };

  programs.bash.enable = true;
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
      pkgs.vimPlugins.nvim-genghis
      pkgs.vimPlugins.nvim-lspconfig
      pkgs.vimPlugins.nvim-solarized-lua
      pkgs.vimPlugins.plenary-nvim
      pkgs.vimPlugins.telescope-nvim
    ];

    initLua = ''
      vim.g.mapleader = " "
      vim.g.maplocalleader = " "

      vim.opt.autoread = true
      vim.opt.termguicolors = true

      dofile("${./neovim/roll.lua}").setup()

      local poetry_root = "/home/damon/workspace/poetry"

      vim.opt.runtimepath:prepend(poetry_root)

      require("poetry").setup({
        root = poetry_root,
      })

      vim.keymap.set("n", "<leader>pd", "<cmd>PoetryDrafts<cr>")
      vim.keymap.set("n", "<leader>pl", "<cmd>PoetryLucky<cr>")
      vim.keymap.set("n", "<leader>pn", "<cmd>PoetryNewDraft<cr>")
      vim.keymap.set("n", "<leader>pr", "<cmd>PoetryDrafts reset<cr>")

      local function apply_solarized_theme()
        local theme_file = io.open("${neovimThemeFile}", "r")
        local mode = theme_file and theme_file:read("*l") or "light"
        if theme_file then
          theme_file:close()
        end
        if mode ~= "dark" then
          mode = "light"
        end

        vim.opt.background = mode
        vim.cmd.colorscheme("solarized")
      end

      apply_solarized_theme()
      vim.api.nvim_create_autocmd("Signal", {
        pattern = "SIGUSR1",
        callback = apply_solarized_theme,
      })

      vim.lsp.enable("hls")
      vim.lsp.enable("marksman")

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

      vim.api.nvim_create_user_command("Rename", function(opts)
        local buffer = vim.api.nvim_get_current_buf()
        local old = vim.api.nvim_buf_get_name(buffer)
        if old == "" then
          vim.notify("Cannot rename an unnamed buffer", vim.log.levels.ERROR)
          return
        end

        local new = vim.fs.joinpath(vim.fs.dirname(old), opts.args)
        local ok, err = vim.uv.fs_rename(old, new)
        if not ok then
          vim.notify(err, vim.log.levels.ERROR)
          return
        end

        vim.api.nvim_buf_set_name(buffer, new)
      end, { nargs = 1, desc = "Rename the current file" })

      local genghis = require("genghis")
      vim.keymap.set("n", "<leader>rn", genghis.renameFile,
        { desc = "Rename file" })
      vim.keymap.set("n", "<leader>yp", genghis.copyFilepathWithTilde,
        { desc = "Copy filepath" })

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
    ignores = [
      ".env"
      ".env*"
      ".local"
    ];
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
      config-file = "?${ghosttyThemeFile}";
    };
  };

  services.darkman = {
    enable = true;
    settings = {
      portal = true;
      usegeoclue = true;
    };
  };

  services.mako.enable = true;

  programs.chromium = {
    enable = true;
    package = pkgs.brave;
    extensions = [
      {
        # Dark Reader
        id = "eimadpbcbfnmbkopoojfekhnkhdbieeh";
      }
      {
        # KeePassXC-Browser
        id = "oboonakemofpalcgghocfoadofidjkkk";
      }
      {
        # Zotero Connector
        id = "ekhagklcjbdpajgpjgmbionohlpdbjgc";
      }
    ];
  };

  programs.fuzzel = {
    enable = true;
    settings.main = {
      include = fuzzelThemeFile;
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
        "bluetooth"
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

      bluetooth = {
        format = "BT {status}";
        format-disabled = "BT disabled";
        format-off = "BT off";
        format-on = "BT on";
        format-connected = "BT {device_alias}";
        format-connected-battery = "BT {device_alias} {device_battery_percentage}%";
        tooltip-format = "{controller_alias}\t{controller_address}";
        tooltip-format-connected = "{controller_alias}\t{controller_address}\n\n{device_enumerate}";
        tooltip-format-enumerate-connected = "{device_alias}\t{device_address}";
        tooltip-format-enumerate-connected-battery = "{device_alias}\t{device_address}\t{device_battery_percentage}%";
        on-click = "${pkgs.bzmenu}/bin/bzmenu -l fuzzel --interactive";
      };

      wireplumber = {
        format = "🔊 {volume}%";
        format-muted = "🔇 muted";
        on-click = "pwvucontrol";
      };
      memory = {
        format = "🧠 {percentage}%";
        on-click = "${pkgs.ghostty}/bin/ghostty -e ${pkgs.bottom}/bin/btm --basic";
      };
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

      #window, #tray, #bluetooth, #network, #wireplumber,
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

  # Waybar's SIGUSR2 reload can leave duplicate bar windows. Ask Home
  # Manager's service switcher to replace the process instead.
  systemd.user.services.waybar.Unit.X-SwitchMethod = "restart";

  xdg.configFile."networkmanager-dmenu/config.ini".text = ''
    [dmenu]
    dmenu_command = fuzzel

    [editor]
    gui = ${pkgs.networkmanagerapplet}/bin/nm-connection-editor
  '';

  systemd.user.services.waybar-theme-watcher = {
    Unit = {
      Description = "Keep the desktop applications in sync with the system color scheme";
      PartOf = [ config.wayland.systemd.target ];
      Wants = [
        "awww-daemon.service"
        "darkman.service"
      ];
      After = [
        "awww-daemon.service"
        "darkman.service"
        "niri.service"
      ];
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

  systemd.user.services.dictate-key-listener = {
    Unit = {
      Description = "Hold Right Alt to dictate into the focused Wayland input";
      PartOf = [ config.wayland.systemd.target ];
      After = [ "niri.service" ];
    };

    Service = {
      ExecStart = "${dictateKeyListener}/bin/dictate-key-listener";
      Restart = "always";
      RestartSec = 2;
    };

    Install.WantedBy = [ "niri.service" ];
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
        command = "${pkgs.systemd}/bin/systemctl suspend-then-hibernate";
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
