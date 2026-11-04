{
  config,
  pkgs,
  cloudscapeRenderer,
  ...
}:

let
  supervisor = pkgs.writeShellApplication {
    name = "cloudscape-supervisor";
    text = ''
      exec ${pkgs.python3}/bin/python3 ${./supervisor.py} \
        --renderer ${cloudscapeRenderer}/bin/papertoy \
        --shader ${./clouds.glsl} \
        --palette-file ${config.xdg.cacheHome}/theme-sync/cloudscape \
        --niri ${pkgs.niri}/bin/niri
    '';
  };
in
{
  systemd.user.services.cloudscape = {
    Unit = {
      Description = "Solarized cloudscape wallpaper (per-output supervision)";
      PartOf = [ config.wayland.systemd.target ];
      Wants = [ "waybar-theme-watcher.service" ];
      After = [
        "niri.service"
        "waybar-theme-watcher.service"
      ];
      # Also stops an old loaded daemon during the first migration.
      Conflicts = [ "awww-daemon.service" ];
    };
    Service = {
      ExecStart = "${supervisor}/bin/cloudscape-supervisor";
      Restart = "on-failure";
      RestartSec = 3;
      TimeoutStopSec = 15;
      KillMode = "control-group";
    };
    Install.WantedBy = [ config.wayland.systemd.target ];
  };
}
