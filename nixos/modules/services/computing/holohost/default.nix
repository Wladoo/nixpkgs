{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.services.holohost;

in {

  ###### interface

  options = {

    services.holohost = {

      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to start the Holohost service.";
      };
      agent = mkOption {
        type = types.path;
        default = null;
        description = "Where the agent string is stored (/dev/usb? talking with ledger Thurs)";
      };

    };
  };

  ###### implementation

  config = mkIf cfg.enable {

    systemd.user.services.holohost = {
      description = "Holohost service";
      serviceConfig = {
        ExecStart = ''
          ${pkgs.holohost}/bin/hcd holohost
        '';
        Restart = "on-failure";
        PrivateTmp = true;
      };
      wantedBy = [ "default.target" ];
    };

    environment.systemPackages = [ pkgs.holochain-go ];
  };
}
