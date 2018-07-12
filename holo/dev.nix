let
  pkgs = import <nixpkgs> {};

  jobs = rec {

    tarball =
      pkgs.releaseTools.sourceTarball {
        name = "hello-tarball";
        src = pkgs.hello;
        buildInputs = (with pkgs; [ pkgs.gettext pkgs.texinfo ]);
      };

    build =
      { system ? builtins.currentSystem }:

      let pkgs = import <nixpkgs> { inherit system; }; in
        pkgs.releaseTools.channel {
        constituents = [build tarball];
        name = "my-channel";
        src = ./.;
      };
  };
in
  jobs
