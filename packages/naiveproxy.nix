{ apps-nixpkgs, system }:
let
  appsPkgs = import apps-nixpkgs { inherit system; };
  version = "150.0.7871.63-1";
in
if system == "x86_64-linux" then
  {
    naiveproxy = appsPkgs.stdenv.mkDerivation {
      pname = "naiveproxy";
      inherit version;

      nativeBuildInputs = [ appsPkgs.autoPatchelfHook ];
      buildInputs = [ appsPkgs.stdenv.cc.cc.lib ];

      src = appsPkgs.fetchurl {
        url = "https://github.com/klzgrad/naiveproxy/releases/download/v${version}/naiveproxy-v${version}-linux-x64.tar.xz";
        hash = "sha256-DE9QbOZqeIGJL9aTK1QsU/wGrCNRmHdWCWxh51PGh78=";
      };

      sourceRoot = "naiveproxy-v${version}-linux-x64";

      installPhase = ''
        runHook preInstall
        install -Dm755 naive "$out/bin/naive"
        runHook postInstall
      '';

      meta.mainProgram = "naive";
    };
  }
else
  { }
