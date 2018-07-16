{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.services.holoport;

in {

  ###### interface

  options = {

    services.holoport = {

      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to start the Holoport service.";
      };

    };
  };

  ###### implementation

  config = mkIf cfg.enable {

    systemd.user.services.holoport = {
      description = "Holoport service";
      serviceConfig = {
        ExecStart = ''
          ${pkgs.holoport}/bin/hcd holoport
        '';
        Restart = "on-failure";
        PrivateTmp = true;
      };
      wantedBy = [ "default.target" ];
    };

    environment.systemPackages = [ pkgs.holochain-go ];
  };
}
