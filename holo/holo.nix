let
  pkgs = import <nixpkgs> {};
  jobs = rec {

    tarball = 
      pkgs.releaseTools.sourceTarball {
        name = "test-tarball";
        srv = <hello>;
        buildInputs = (with pkgs; [ gettext texLive texinfo]);
      };
    
    build = 
      { system ? builtins.current.System}:

      let pkgs = import <nixpkgs> {inherit system; }; in
      pkgs.releaseTools.nixBuild {
        name = "hello";
        src = jobs.tarball;
        configureFlahs = [ "--disable-silent-rules" ];
      };
  };
in
  jobs

