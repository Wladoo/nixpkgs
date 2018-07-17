{ nixpkgs ? { outPath = (import ../lib).cleanSource ./..; revCount = 56789; shortRev = "gfedcba"; }
, stableBranch ? false
, supportedSystems ? [ "x86_64-linux" "aarch64-linux" ]
}:

with import ../pkgs/top-level/release-lib.nix { inherit supportedSystems; };
with import ../lib;

let

  version = fileContents ../.version;
  versionSuffix =
    (if stableBranch then "." else "pre") + "${toString nixpkgs.revCount}.${nixpkgs.shortRev}";

  importTest = fn: args: system: import fn ({
    inherit system;
  } // args);

  callTestOnMatchingSystems = systems: fn: args:
    forMatchingSystems
      systems
      (system: hydraJob (importTest fn args system));
  callTest = callTestOnMatchingSystems supportedSystems;

  callSubTests = callSubTestsOnMatchingSystems supportedSystems;
  callSubTestsOnMatchingSystems = systems: fn: args: let
    discover = attrs: let
      subTests = filterAttrs (const (hasAttr "test")) attrs;
    in mapAttrs (const (t: hydraJob t.test)) subTests;

    discoverForSystem = system: mapAttrs (_: test: {
      ${system} = test;
    }) (discover (importTest fn args system));

  in foldAttrs mergeAttrs {} (map discoverForSystem (intersectLists systems supportedSystems));

  pkgs = import nixpkgs { system = "x86_64-linux"; };


  versionModule =
    { system.nixos.versionSuffix = versionSuffix;
      system.nixos.revision = nixpkgs.rev or nixpkgs.shortRev;
    };


  makeIso =
    { module, type, maintainers ? ["eelco"], system }:

    with import nixpkgs { inherit system; };

    hydraJob ((import lib/eval-config.nix {
      inherit system;
      modules = [ module versionModule { isoImage.isoBaseName = "nixos-${type}"; } ];
    }).config.system.build.isoImage);


  makeSdImage =
    { module, maintainers ? ["dezgeg"], system }:

    with import nixpkgs { inherit system; };

    hydraJob ((import lib/eval-config.nix {
      inherit system;
      modules = [ module versionModule ];
    }).config.system.build.sdImage);


  makeSystemTarball =
    { module, maintainers ? ["viric"], system }:

    with import nixpkgs { inherit system; };

    let

      config = (import lib/eval-config.nix {
        inherit system;
        modules = [ module versionModule ];
      }).config;

      tarball = config.system.build.tarball;

    in
      tarball //
        { meta = {
            description = "NixOS system tarball for ${system} - ${stdenv.platform.name}";
            maintainers = map (x: lib.maintainers.${x}) maintainers;
          };
          inherit config;
        };


  makeClosure = module: buildFromConfig module (config: config.system.build.toplevel);


  buildFromConfig = module: sel: forAllSystems (system: hydraJob (sel (import ./lib/eval-config.nix {
    inherit system;
    modules = [ module versionModule ] ++ singleton
      ({ config, lib, ... }:
      { fileSystems."/".device  = mkDefault "/dev/sda1";
        boot.loader.grub.device = mkDefault "/dev/sda";
      });
  }).config));

  makeNetboot = config:
    let
      configEvaled = import lib/eval-config.nix config;
      build = configEvaled.config.system.build;
      kernelTarget = configEvaled.pkgs.stdenv.platform.kernelTarget;
    in
      pkgs.symlinkJoin {
        name = "netboot";
        paths = [
          build.netbootRamdisk
          build.kernel
          build.netbootIpxeScript
        ];
        postBuild = ''
          mkdir -p $out/nix-support
          echo "file ${kernelTarget} $out/${kernelTarget}" >> $out/nix-support/hydra-build-products
          echo "file initrd $out/initrd" >> $out/nix-support/hydra-build-products
          echo "file ipxe $out/netboot.ipxe" >> $out/nix-support/hydra-build-products
        '';
        preferLocalBuild = true;
      };

in rec {

  channel = import lib/make-channel.nix { inherit pkgs nixpkgs version versionSuffix; };

  manual = buildFromConfig ({ pkgs, ... }: { }) (config: config.system.build.manual.manual);
  manualEpub = (buildFromConfig ({ pkgs, ... }: { }) (config: config.system.build.manual.manualEpub));
  manpages = buildFromConfig ({ pkgs, ... }: { }) (config: config.system.build.manual.manpages);
  manualGeneratedSources = buildFromConfig ({ pkgs, ... }: { }) (config: config.system.build.manual.generatedSources);
  options = (buildFromConfig ({ pkgs, ... }: { }) (config: config.system.build.manual.optionsJSON)).x86_64-linux;


  # Build the initial ramdisk so Hydra can keep track of its size over time.
  initialRamdisk = buildFromConfig ({ pkgs, ... }: { }) (config: config.system.build.initialRamdisk);

  netboot = forMatchingSystems [ "x86_64-linux" "aarch64-linux" ] (system: makeNetboot {
    inherit system;
    modules = [
      ./modules/installer/netboot/netboot-minimal.nix
      versionModule
    ];
  });

  iso_minimal = forAllSystems (system: makeIso {
    module = ./modules/installer/cd-dvd/installation-cd-minimal.nix;
    type = "minimal";
    inherit system;
  });

  iso_graphical = forMatchingSystems [ "x86_64-linux" ] (system: makeIso {
    module = ./modules/installer/cd-dvd/installation-cd-graphical-kde.nix;
    type = "graphical";
    inherit system;
  });

  # A variant with a more recent (but possibly less stable) kernel
  # that might support more hardware.
  iso_minimal_new_kernel = forMatchingSystems [ "x86_64-linux" ] (system: makeIso {
    module = ./modules/installer/cd-dvd/installation-cd-minimal-new-kernel.nix;
    type = "minimal-new-kernel";
    inherit system;
  });

  sd_image = forMatchingSystems [ "aarch64-linux" ] (system: makeSdImage {
    module = ./modules/installer/cd-dvd/sd-image-aarch64.nix;
    inherit system;
  });

  # A bootable VirtualBox virtual appliance as an OVA file (i.e. packaged OVF).
  ova = forMatchingSystems [ "x86_64-linux" ] (system:

    with import nixpkgs { inherit system; };

    hydraJob ((import lib/eval-config.nix {
      inherit system;
      modules =
        [ versionModule
          ./modules/installer/virtualbox-demo.nix
        ];
    }).config.system.build.virtualBoxOVA)

  );


  # Ensure that all packages used by the minimal NixOS config end up in the channel.
  dummy = forAllSystems (system: pkgs.runCommand "dummy"
    { toplevel = (import lib/eval-config.nix {
        inherit system;
        modules = singleton ({ config, pkgs, ... }:
          { fileSystems."/".device  = mkDefault "/dev/sda1";
            boot.loader.grub.device = mkDefault "/dev/sda";
          });
      }).config.system.build.toplevel;
      preferLocalBuild = true;
    }
    "mkdir $out; ln -s $toplevel $out/dummy");


  # Provide a tarball that can be unpacked into an SD card, and easily
  # boot that system from uboot (like for the sheevaplug).
  # The pc variant helps preparing the expression for the system tarball
  # in a machine faster than the sheevpalug
  # Is this tarball what we could deliver to the manufacturer?
  /*
  system_tarball_pc = forAllSystems (system: makeSystemTarball {
    module = ./modules/installer/cd-dvd/system-tarball-pc.nix;
    Inherit system;
  });
  */

  # Provide container tarball for lxc, libvirt-lxc, docker-lxc, ...
  containerTarball = forAllSystems (system: makeSystemTarball {
    module = ./modules/virtualisation/lxc-container.nix;
    inherit system;
  });

  /*
  system_tarball_fuloong2f =
    assert builtins.currentSystem == "mips64-linux";
    makeSystemTarball {
      module = ./modules/installer/cd-dvd/system-tarball-fuloong2f.nix;
      system = "mips64-linux";
    };

  system_tarball_sheevaplug =
    assert builtins.currentSystem == "armv5tel-linux";
    makeSystemTarball {
      module = ./modules/installer/cd-dvd/system-tarball-sheevaplug.nix;
      system = "armv5tel-linux";
    };
  */


  # Run the tests for each platform.  You can run a test by doing
  # e.g. ‘nix-build -A tests.login.x86_64-linux’, or equivalently,
  # ‘nix-build tests/login.nix -A result’.
  tests.containers-ipv4 = callTest tests/containers-ipv4.nix {};
  tests.containers-ipv6 = callTest tests/containers-ipv6.nix {};
  tests.containers-bridge = callTest tests/containers-bridge.nix {};
  tests.containers-imperative = callTest tests/containers-imperative.nix {};
  tests.containers-extra_veth = callTest tests/containers-extra_veth.nix {};
  tests.containers-physical_interfaces = callTest tests/containers-physical_interfaces.nix {};
  tests.containers-restart_networking = callTest tests/containers-restart_networking.nix {};
  tests.containers-tmpfs = callTest tests/containers-tmpfs.nix {};
  tests.containers-hosts = callTest tests/containers-hosts.nix {};
  tests.containers-macvlans = callTest tests/containers-macvlans.nix {};
  tests.dnscrypt-proxy = callTestOnMatchingSystems ["x86_64-linux"] tests/dnscrypt-proxy.nix {};
  tests.ecryptfs = callTest tests/ecryptfs.nix {};
  tests.etcd = callTestOnMatchingSystems ["x86_64-linux"] tests/etcd.nix {};
  tests.ec2-nixops = (callSubTestsOnMatchingSystems ["x86_64-linux"] tests/ec2.nix {}).boot-ec2-nixops or {};
  tests.ec2-config = (callSubTestsOnMatchingSystems ["x86_64-linux"] tests/ec2.nix {}).boot-ec2-config or {};
  tests.firewall = callTest tests/firewall.nix {};
  tests.kernel-copperhead = callTest tests/kernel-copperhead.nix {};
  tests.kernel-latest = callTest tests/kernel-latest.nix {};
  tests.kernel-lts = callTest tests/kernel-lts.nix {};
  tests.latestKernel.login = callTest tests/login.nix { latestKernel = true; };
  tests.ldap = callTest tests/ldap.nix {};
  tests.login = callTest tests/login.nix {};
  #tests.logstash = callTest tests/logstash.nix {};
  tests.networking.networkd = callSubTests tests/networking.nix { networkd = true; };
  tests.networking.scripted = callSubTests tests/networking.nix { networkd = false; };
  # TODO: put in networking.nix after the test becomes more complete
  #tests.pgjwt = callTest tests/pgjwt.nix {};
  tests.predictable-interface-names = callSubTests tests/predictable-interface-names.nix {};
  tests.simple = callTest tests/simple.nix {};
  tests.systemd = callTest tests/systemd.nix {};

  /* Build a bunch of typical closures so that Hydra can keep track of
     the evolution of closure sizes. */

  closures = {

    smallContainer = makeClosure ({ pkgs, ... }:
      { boot.isContainer = true;
        services.openssh.enable = true;
      });

    tinyContainer = makeClosure ({ pkgs, ... }:
      { boot.isContainer = true;
        imports = [ modules/profiles/minimal.nix ];
      });

    ec2 = makeClosure ({ pkgs, ... }:
      { imports = [ modules/virtualisation/amazon-image.nix ];
      });
  };
}
