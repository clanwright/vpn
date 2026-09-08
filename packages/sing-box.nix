{ apps-nixpkgs, system }:
let
  appsPkgs = import apps-nixpkgs { inherit system; };
  version = "1.14.0";
in
if system == "x86_64-linux" then
  {
    sing-box = appsPkgs.stdenv.mkDerivation {
      pname = "sing-box";
      inherit version;

      nativeBuildInputs = [ appsPkgs.autoPatchelfHook ];
      buildInputs = [ appsPkgs.stdenv.cc.cc.lib ];

      src = appsPkgs.fetchurl {
        url = "https://github.com/SagerNet/sing-box/releases/download/v${version}/sing-box-${version}-linux-amd64.tar.gz";
        hash = "sha256-I3XeaZn09Wq0a0/F3fJqarodPmGg9Ofd7C9GkEV9X2M=";
      };

      sourceRoot = "sing-box-${version}-linux-amd64";

      installPhase = ''
        runHook preInstall
        install -Dm755 sing-box "$out/bin/sing-box"
        install -Dm755 libcronet.so "$out/bin/libcronet.so"
        install -Dm644 LICENSE "$out/share/licenses/sing-box/LICENSE"
        runHook postInstall
      '';

      doInstallCheck = true;
      installCheckPhase = ''
        runHook preInstallCheck

        "$out/bin/sing-box" version | tee version.txt
        grep -F "sing-box version ${version}" version.txt
        grep -F "with_naive_outbound" version.txt

        cat > naive.json <<'EOF'
        {
          "log": { "disabled": true },
          "outbounds": [
            {
              "type": "naive",
              "tag": "naive",
              "server": "example.com",
              "server_port": 443,
              "username": "fixture",
              "password": "fixture",
              "tls": {
                "enabled": true,
                "server_name": "example.com"
              }
            }
          ],
          "route": { "final": "naive" }
        }
        EOF
        "$out/bin/sing-box" check -c naive.json

        runHook postInstallCheck
      '';

      meta = {
        description = "Universal proxy platform with the official NaiveProxy runtime";
        homepage = "https://sing-box.sagernet.org";
        license = appsPkgs.lib.licenses.gpl3Plus;
        mainProgram = "sing-box";
        platforms = [ "x86_64-linux" ];
      };
    };
  }
else
  { }
