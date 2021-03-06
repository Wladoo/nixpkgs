{ stdenv
, fetchFromGitHub
, zlib
, pkgs
, mpi ? false
}:

stdenv.mkDerivation rec {
  pname = "RAxML";
  version = "8.2.11";
  name = "${pname}-${version}";

  src = fetchFromGitHub {
    owner = "stamatak";
    repo = "standard-${pname}";
    rev = "v${version}";
    sha256 = "08fmqrr7y5a2fmmrgfz2p0hmn4mn71l5yspxfcwwsqbw6vmdfkhg";
  };

  buildInputs = if mpi then [ pkgs.openmpi ] else [];

  # TODO darwin, AVX and AVX2 makefile targets
  buildPhase = if mpi then ''
      make -f Makefile.MPI.gcc
    '' else ''
      make -f Makefile.SSE3.PTHREADS.gcc
    '';

  installPhase = if mpi then ''
    mkdir -p $out/bin && cp raxmlHPC-MPI $out/bin
  '' else ''
    mkdir -p $out/bin && cp raxmlHPC-PTHREADS-SSE3 $out/bin
  '';

  meta = with stdenv.lib; {
    description = "A tool for Phylogenetic Analysis and Post-Analysis of Large Phylogenies";
    license = licenses.gpl3;
    homepage = https://sco.h-its.org/exelixis/web/software/raxml/;
    maintainers = [ maintainers.unode ];
    platforms = [ "i686-linux" "x86_64-linux" ];
  };
}
