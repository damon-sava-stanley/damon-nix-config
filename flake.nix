{
  description = "NixOS configuration for deeley";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    dictate-src = {
      url = "github:msf/dictate";
      flake = false;
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      dictate-src,
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      unstablePkgs = import nixpkgs-unstable {
        inherit system;
      };
    in
    {
      nixosConfigurations.deeley = nixpkgs.lib.nixosSystem {
        inherit system;

        modules = [
          ./hosts/deeley
          home-manager.nixosModules.home-manager
          {
            nixpkgs.config.allowUnfreePredicate =
              pkg:
              builtins.elem (nixpkgs.lib.getName pkg) [
                "brave"
                "dropbox"
                "firefox-bin"
                "firefox-bin-unwrapped"
                "steam"
                "steam-unwrapped"
              ];

            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = {
                inherit dictate-src unstablePkgs;
              };
              users.damon = import ./home/damon;
            };
          }
        ];
      };

      checks.${system} = {
        deeley = self.nixosConfigurations.deeley.config.system.build.toplevel;
        brave-extensions =
          let
            homeConfig = self.nixosConfigurations.deeley.config.home-manager.users.damon;
          in
          pkgs.runCommandLocal "brave-extensions-test"
            {
              nativeBuildInputs = [ pkgs.bash ];
              BRAVE_EXTENSION_IDS = builtins.concatStringsSep " " (
                map (extension: extension.id) homeConfig.programs.chromium.extensions
              );
              HOME_PACKAGE_NAMES = builtins.concatStringsSep " " (
                map nixpkgs.lib.getName homeConfig.home.packages
              );
            }
            ''
              bash ${./tests/brave-extensions.bash}
              touch "$out"
            '';
        zmk-studio =
          let
            systemConfig = self.nixosConfigurations.deeley.config;
            homeConfig = self.nixosConfigurations.deeley.config.home-manager.users.damon;
          in
          pkgs.runCommandLocal "zmk-studio-test"
            {
              nativeBuildInputs = [ pkgs.bash ];
              HOME_PACKAGE_NAMES = builtins.concatStringsSep " " (
                map nixpkgs.lib.getName homeConfig.home.packages
              );
              DAMON_GROUPS = builtins.concatStringsSep " " systemConfig.users.users.damon.extraGroups;
            }
            ''
              bash ${./tests/zmk-studio.bash}
              touch "$out"
            '';
        zotero-extensions =
          let
            homeConfig = self.nixosConfigurations.deeley.config.home-manager.users.damon;
            zoteroPackage = builtins.head (
              builtins.filter (package: nixpkgs.lib.getName package == "zotero") homeConfig.home.packages
            );
          in
          pkgs.runCommandLocal "zotero-extensions-test"
            {
              nativeBuildInputs = [ pkgs.coreutils ];
              ZOTERO_PACKAGE = zoteroPackage;
            }
            ''
              bash ${./tests/zotero-extensions.bash}
              touch "$out"
            '';
        waybar-bluetooth =
          let
            systemConfig = self.nixosConfigurations.deeley.config;
            homeConfig = systemConfig.home-manager.users.damon;
            waybarMain = homeConfig.programs.waybar.settings.mainBar;
          in
          pkgs.runCommandLocal "waybar-bluetooth-test"
            {
              nativeBuildInputs = [ pkgs.bash ];
              BLUETOOTH_ENABLED = if systemConfig.hardware.bluetooth.enable then "true" else "false";
              BLUETOOTH_POWER_ON_BOOT = if systemConfig.hardware.bluetooth.powerOnBoot then "true" else "false";
              BLUETOOTH_EXPERIMENTAL =
                if systemConfig.hardware.bluetooth.settings.General.Experimental then "true" else "false";
              MAKO_ENABLED = if homeConfig.services.mako.enable then "true" else "false";
              WAYBAR_RIGHT_MODULES = builtins.concatStringsSep " " waybarMain.modules-right;
              WAYBAR_BLUETOOTH_CLICK = waybarMain.bluetooth.on-click or "unset";
            }
            ''
              bash ${./tests/waybar-bluetooth.bash}
              touch "$out"
            '';
        ghostty-theme-sync =
          pkgs.runCommandLocal "ghostty-theme-sync-test"
            {
              nativeBuildInputs = [
                pkgs.bash
                pkgs.coreutils
                pkgs.diffutils
                pkgs.gnugrep
              ];
            }
            ''
              GHOSTTY_SYNC_SCRIPT=${./home/damon/theme-sync/ghostty.sh} \
                bash ${./tests/ghostty-theme-sync.bash}
              touch "$out"
            '';
        niri-toggle-monitors =
          pkgs.runCommandLocal "niri-toggle-monitors-test"
            {
              nativeBuildInputs = [
                pkgs.bash
                pkgs.coreutils
                pkgs.jq
              ];
              NIRI_TOGGLE_SCRIPT = ./home/damon/niri/toggle-monitors.sh;
            }
            ''
              bash ${./tests/niri-toggle-monitors.bash}
              touch "$out"
            '';
        dictate-config =
          let
            systemConfig = self.nixosConfigurations.deeley.config;
            homeConfig = systemConfig.home-manager.users.damon;
            keyboard =
              systemConfig.services.keyd.keyboards.dictation or {
                ids = [ ];
                settings = { };
              };
            listener =
              homeConfig.systemd.user.services.dictate-key-listener or {
                Install.WantedBy = [ ];
                Service.ExecStart = "unset";
              };
          in
          pkgs.runCommandLocal "dictate-config-test"
            {
              nativeBuildInputs = [ pkgs.bash ];
              KEYD_ENABLED = if systemConfig.services.keyd.enable then "true" else "false";
              KEYD_IDS = builtins.concatStringsSep " " keyboard.ids;
              KEYD_RIGHTALT = keyboard.settings.main.rightalt or "unset";
              KEYD_DICTATE_LAYER = if keyboard.settings ? dictate then "true" else "false";
              DAMON_GROUPS = builtins.concatStringsSep " " systemConfig.users.users.damon.extraGroups;
              KEYD_GROUP_DEFINED = if systemConfig.users.groups ? keyd then "true" else "false";
              KEYD_SERVICE_GROUP = systemConfig.systemd.services.keyd.serviceConfig.Group or "unset";
              LISTENER_WANTED_BY = builtins.concatStringsSep " " listener.Install.WantedBy;
              LISTENER_EXEC_START = listener.Service.ExecStart;
            }
            ''
              bash ${./tests/dictate-config.bash}
              touch "$out"
            '';
        dictate-control =
          pkgs.runCommandLocal "dictate-control-test"
            {
              nativeBuildInputs = [
                pkgs.bash
                pkgs.coreutils
              ];
              DICTATE_CONTROL_SCRIPT = ./home/damon/dictate/control.sh;
              TEST_BASH = "${pkgs.bash}/bin/bash";
            }
            ''
              bash ${./tests/dictate-control.bash}
              touch "$out"
            '';
        dictate-listener =
          pkgs.runCommandLocal "dictate-listener-test"
            {
              nativeBuildInputs = [
                pkgs.bash
                pkgs.coreutils
              ];
              DICTATE_LISTENER_SCRIPT = ./home/damon/dictate/listen.sh;
              TEST_BASH = "${pkgs.bash}/bin/bash";
            }
            ''
              bash ${./tests/dictate-listener.bash}
              touch "$out"
            '';
        dictate-runtime =
          let
            homePackages = self.nixosConfigurations.deeley.config.home-manager.users.damon.home.packages;
            dictatePackage = builtins.head (
              builtins.filter (package: nixpkgs.lib.getName package == "dictate") homePackages
            );
            controllerPackage = builtins.head (
              builtins.filter (package: nixpkgs.lib.getName package == "dictate-control") homePackages
            );
          in
          pkgs.runCommandLocal "dictate-runtime-test"
            {
              nativeBuildInputs = [ pkgs.gnugrep ];
            }
            ''
              test -x ${dictatePackage}/bin/dictate
              test -x ${dictatePackage}/bin/whisper-stream
              ${dictatePackage}/bin/dictate --help 2>&1 | grep -F -- "list-devices"
              ${dictatePackage}/bin/whisper-stream --help 2>&1 | grep -F -- "--step"
              grep -F -- "wtype" ${dictatePackage}/bin/dictate
              grep -F -- "ggml-large-v3-turbo-q5_0.bin" ${controllerPackage}/bin/dictate-control
              touch "$out"
            '';
        neovim-roll =
          pkgs.runCommandLocal "neovim-roll-test"
            {
              nativeBuildInputs = [ pkgs.neovim ];
            }
            ''
              ROLL_LUA=${./home/damon/neovim/roll.lua} \
                nvim --headless -u NONE -i NONE -l ${./tests/neovim-roll.lua}
              touch "$out"
            '';
        waybar-lifecycle =
          let
            waybarService =
              self.nixosConfigurations.deeley.config.home-manager.users.damon.systemd.user.services.waybar;
          in
          pkgs.runCommandLocal "waybar-lifecycle-test"
            {
              nativeBuildInputs = [
                pkgs.bash
                pkgs.gnugrep
              ];
              HOME_CONFIG = ./home/damon/default.nix;
              WAYBAR_SWITCH_METHOD =
                if waybarService.Unit.X-SwitchMethod == null then "unset" else waybarService.Unit.X-SwitchMethod;
            }
            ''
              bash ${./tests/waybar-lifecycle.bash}
              touch "$out"
            '';
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          pkgs.nodejs
          pkgs.playwright-driver.browsers
          (pkgs.python3.withPackages (
            pythonPackages: with pythonPackages; [
              playwright
              pytest-playwright
            ]
          ))
        ];

        env = {
          PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
          PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
        };
      };

      formatter.${system} = pkgs.nixfmt;
    };
}
