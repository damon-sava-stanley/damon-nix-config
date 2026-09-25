{ pkgs, ... }:

{
  systemd.services.cloudflared = {
    description = "Cloudflare Tunnel";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel --no-autoupdate run --token-file %d/tunnel-token";
      LoadCredential = "tunnel-token:/home/damon/.cloudflared/tunnel-token";
      DynamicUser = true;
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };
}
