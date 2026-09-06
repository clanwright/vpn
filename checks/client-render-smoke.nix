{
  inputs,
  pkgs,
  root,
  self,
}:
let
  lib = inputs.nixpkgs.lib;
  fixture = import ./fixtures/example-clan.nix;
  supportNames = [
    "edge-wildcard-certificate"
    "network-caddy"
    "network-certificates"
  ];
  serviceNames = builtins.filter (name: !(builtins.elem name supportNames)) (
    builtins.attrNames fixture.instances
  );
  consumer = (import ./lib/consumer.nix { inherit inputs root self; }) {
    instanceNames = serviceNames;
  };
  generatorScript = consumer.machine.systemd.services.mihomo-client-caddy-fixture.script;
  contextFor =
    derivationName: source:
    let
      context = lib.filterAttrs (drvPath: _: lib.hasSuffix "-${derivationName}.drv" drvPath) (
        builtins.getContext source
      );
      matches = builtins.attrNames context;
    in
    if builtins.length matches != 1 then
      throw "Expected one derivation context for ${derivationName}, found ${toString (builtins.length matches)}"
    else
      context;
  pathFromScript =
    derivationName: source:
    let
      matches = builtins.match ".*(/nix/store/[^ ]*${derivationName}).*" source;
    in
    if matches == null then
      throw "Expected ${derivationName} path in client renderer"
    else
      builtins.appendContext (builtins.head matches) (contextFor derivationName source);
  mihomoTemplate = pathFromScript "mihomo-client-fixture-probe.template.json" generatorScript;
  singBoxTemplate = pathFromScript "client-profile-fixture-probe.template.json" generatorScript;
in
pkgs.runCommand "vpn-client-render-smoke"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnused
      pkgs.jq
      pkgs.yq-go
      self.packages.${pkgs.system}.mihomo
      self.packages.${pkgs.system}.sing-box
    ];
  }
  ''
    set -euo pipefail
    export HOME="$TMPDIR"
    export XDG_CONFIG_HOME="$TMPDIR/.config"

    replace_placeholders() {
      local input="$1"
      local output="$2"
      sed -E \
        -e 's/__MIHOMO_VLESS_UUID_[A-Za-z0-9_-]+__/00000000-0000-4000-8000-000000000001/g' \
        -e 's#__MIHOMO_AMNEZIAWG_PRIVATE_KEY_[A-Za-z0-9_-]+__#AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=#g' \
        -e 's/__MIHOMO_HY2_PASSWORD_[A-Za-z0-9_-]+__/fixture-password/g' \
        -e 's/__MIHOMO_HY2_OBFS_PASSWORD_[A-Za-z0-9_-]+__/fixture-password/g' \
        -e 's/__PROFILE_NAIVE_PASSWORD_[A-Za-z0-9_-]+__/fixture-password/g' \
        "$input" >"$output"
    }

    replace_placeholders ${lib.escapeShellArg mihomoTemplate} "$TMPDIR/mihomo.json"
    replace_placeholders ${lib.escapeShellArg singBoxTemplate} "$TMPDIR/profile.json"
    if grep -Eq '__MIHOMO_|__PROFILE_' "$TMPDIR/mihomo.json" "$TMPDIR/profile.json"; then
      echo 'renderer left a secret placeholder unresolved' >&2
      exit 1
    fi

    yq -P -o=yaml '.' "$TMPDIR/mihomo.json" >"$TMPDIR/mihomo.yaml"
    mihomo -t -f "$TMPDIR/mihomo.yaml"
    jq -e '
      ([.proxies[].type] | contains(["vless", "hysteria2", "wireguard"]))
      and ([."proxy-groups"[].name] | contains(["GLOBAL", "PROXY", "PROXY-AUTO"]))
    ' "$TMPDIR/mihomo.json" >/dev/null

    jq -e '
      ([.outbounds[].type] | contains(["naive"]))
      and ([.route.rule_set[].tag] | contains(["personal_proxy_domains"]))
    ' "$TMPDIR/profile.json" >/dev/null
    sing-box check -D "$TMPDIR" -c "$TMPDIR/profile.json"

    mkdir -p "$out"
    cp "$TMPDIR/mihomo.yaml" "$out/mihomo.yaml"
    cp "$TMPDIR/profile.json" "$out/profile.json"
  ''
