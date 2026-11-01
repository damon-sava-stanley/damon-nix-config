{ pkgs, ... }:
let
  powerPolicy = pkgs.writeShellApplication {
    name = "power-policy";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      exec ${pkgs.python3}/bin/python3 ${../../scripts/power-policy.py} "$@"
    '';
  };
in
{
  environment.systemPackages = [ powerPolicy ];

  # Closed-lid external-monitor use is normal. Only session inactivity triggers sleep.
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
  };
  systemd.sleep.settings.Sleep = {
    HibernateDelaySec = "5min";
    HibernateOnACPower = false;
  };
}
