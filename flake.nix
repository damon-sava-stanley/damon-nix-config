{
  description = "NixOS configuration for deeley";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

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
                inherit unstablePkgs;
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
