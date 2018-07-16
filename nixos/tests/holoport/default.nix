# This test runs holohost and checks if it works

import ./make-test.nix ({ pkgs, ...} : {
  name = "holohost";
  meta = with pkgs.stdenv.lib.maintainers; {
    maintainers = [ gavin ];
  };

  nodes = {
    holohost1 = { config, pkgs, ... }: {
      virtualisation.memorySize = 768;
      services.holohost = {
        enable = true;
        };
      };
    };


  testScript = ''
    $holohost1->start();
    $holohost1->waitForUnit("holohost.service");
    $holohost1->waitUntilSucceeds("curl http://localhost:8101");
  '';
})
