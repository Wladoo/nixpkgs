{ lowPrio, newScope, stdenv, targetPlatform, cmake, libstdcxxHook
, libxml2, python2, isl, fetchurl, overrideCC, wrapCC, ccWrapperFun
, darwin
}:

let
  callPackage = newScope (self // { inherit stdenv cmake libxml2 python2 isl release_version version fetch; });

  release_version = "6.0.1";
  version = release_version; # differentiating these is important for rc's

  fetch = name: sha256: fetchurl {
    url = "http://releases.llvm.org/${release_version}/${name}-${version}.src.tar.xz";
    inherit sha256;
  };

  compiler-rt_src = fetch "compiler-rt" "1fcr3jn24yr8lh36nc0c4ikli4744i2q9m1ik67p1jymwwaixkgl";
  clang-tools-extra_src = fetch "clang-tools-extra" "1w8ml7fyn4vyxmy59n2qm4r1k1kgwgwkaldp6m45fdv4g0kkfbhd";

  # Add man output without introducing extra dependencies.
  overrideManOutput = drv:
    let drv-manpages = drv.override { enableManpages = true; }; in
    drv // { man = drv-manpages.out; /*outputs = drv.outputs ++ ["man"];*/ };

  llvm = callPackage ./llvm.nix {
    inherit compiler-rt_src stdenv;
  };

  clang-unwrapped = callPackage ./clang {
    inherit clang-tools-extra_src stdenv;
  };

  self = {
    llvm = overrideManOutput llvm;
    clang-unwrapped = overrideManOutput clang-unwrapped;

    libclang = self.clang-unwrapped.lib;
    llvm-manpages = lowPrio self.llvm.man;
    clang-manpages = lowPrio self.clang-unwrapped.man;

    clang = if stdenv.cc.isGNU then self.libstdcxxClang else self.libcxxClang;

    libstdcxxClang = ccWrapperFun {
      cc = self.clang-unwrapped;
      /* FIXME is this right? */
      inherit (stdenv.cc) bintools libc nativeTools nativeLibc;
      extraPackages = [ libstdcxxHook ];
    };

    libcxxClang = ccWrapperFun {
      cc = self.clang-unwrapped;
      /* FIXME is this right? */
      inherit (stdenv.cc) bintools libc nativeTools nativeLibc;
      extraPackages = [ self.libcxx self.libcxxabi ];
    };

    stdenv = stdenv.override (drv: {
      allowedRequisites = null;
      cc = self.clang;
    });

    libcxxStdenv = stdenv.override (drv: {
      allowedRequisites = null;
      cc = self.libcxxClang;
    });

    lld = callPackage ./lld.nix {};

    lldb = callPackage ./lldb.nix {};

    libcxx = callPackage ./libc++ {};

    libcxxabi = callPackage ./libc++abi.nix {};

    openmp = callPackage ./openmp.nix {};
  };

in self
