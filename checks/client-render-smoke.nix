{
  inputs,
  pkgs,
  root,
  self,
}:
let
  lib = inputs.nixpkgs.lib;
  fixture = import ./fixtures/example-clan.nix;
  fixtureMachineName = fixture.machineName or "vpn-fixture";
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
  zeroNaiveInstances = fixture.instances // {
    vpn-client-profiles = lib.recursiveUpdate fixture.instances.vpn-client-profiles {
      roles.publisher.machines.vpn-fixture.settings.providerRefs = builtins.filter (
        ref: ref.protocol != "naiveproxy"
      ) fixture.instances.vpn-client-profiles.roles.publisher.machines.vpn-fixture.settings.providerRefs;
    };
  };
  zeroNaiveConsumer = inputs.clan-core.lib.clan {
    self.inputs = {
      vpn = self;
      inherit (inputs) network;
      self.clan = zeroNaiveConsumer.config;
    };
    specialArgs.clan-core = inputs.clan-core;
    directory = builtins.path {
      path = root + /checks/fixtures;
      name = "vpn-consumer-zero-naive-fixture";
    };
    imports = [
      self.clanModule
      {
        machines.${fixtureMachineName} = _: fixture.machine;
        inventory = {
          meta.name = "vpn-consumer-zero-naive-fixture";
          machines.${fixtureMachineName} = { };
          instances = zeroNaiveInstances;
        };
      }
    ];
  };
  zeroNaiveGeneratorScript =
    zeroNaiveConsumer.config.nixosConfigurations.${fixtureMachineName}.config.systemd.services.mihomo-client-caddy-fixture.script;
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
  zeroNaiveSingBoxTemplate = pathFromScript "client-profile-fixture-probe.template.json" zeroNaiveGeneratorScript;
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
    replace_placeholders ${lib.escapeShellArg zeroNaiveSingBoxTemplate} "$TMPDIR/zero-naive-profile.json"
    if grep -Eq '__MIHOMO_|__PROFILE_' \
      "$TMPDIR/mihomo.json" "$TMPDIR/profile.json" "$TMPDIR/zero-naive-profile.json"; then
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
      def rule_index(filter):
        first(range(0; (.route.rules | length)) as $index | select(.route.rules[$index] | filter) | $index);
      def proxied_rule_sets:
        [.route.rules[] | select(.outbound == "PROXY") | .rule_set] | flatten | unique;
      ([.route.rule_set[].tag] | contains(["personal_proxy_domains"]))
      and (.outbounds | map(select(.type == "naive")) | length == 1)
      and (first(.outbounds[] | select(.type == "naive")) as $naive
        | ($naive | .server == "192.0.2.10"
          and .server_port == 443
          and .username == "probe"
          and .insecure_concurrency == 0
          and .udp_over_tcp == false
          and .quic == false
          and .tls.enabled == true
          and .tls.server_name == "site.example.invalid")
        and (.route.final == "DIRECT")
        and (.outbounds[] | select(.tag == "PROXY")
          | .type == "selector"
          and .default == "PROXY-AUTO"
          and .outbounds == ["PROXY-AUTO", $naive.tag])
        and (.outbounds[] | select(.tag == "PROXY-AUTO")
          | .type == "urltest"
          and .outbounds == [$naive.tag])
        and (all(.route.rule_set[]; .download_detour == $naive.tag)))
      and (rule_index(.action == "hijack-dns") as $dns
        | rule_index(.ip_is_private == true and .outbound == "DIRECT") as $private
        | rule_index(.ip_cidr == ["224.0.0.0/4"] and .outbound == "DIRECT") as $multicast
        | rule_index(.network == "udp" and .action == "reject") as $udp
        | rule_index(.rule_set == "personal_proxy_domains" and .outbound == "PROXY") as $proxy
        | $dns < $udp
          and $private < $udp
          and $multicast < $udp
          and $udp < $proxy)
      and (first(.route.rules[] | select(.network == "udp" and .action == "reject")) as $udp
        | ($udp | has("port") | not)
        and (($udp.rule_set | unique) == proxied_rule_sets))
    ' "$TMPDIR/profile.json" >/dev/null
    sing-box check -D "$TMPDIR" -c "$TMPDIR/profile.json"

    jq -e '
      ([.outbounds[] | select(.type == "naive" or .type == "urltest")] | length == 0)
      and (.outbounds[] | select(.tag == "PROXY")
        | .type == "selector"
        and .default == "DIRECT"
        and .outbounds == ["DIRECT"])
      and ([.route.rules[] | select(.network == "udp" and .action == "reject")] | length == 0)
      and (all(.route.rule_set[]; has("download_detour") | not))
    ' "$TMPDIR/zero-naive-profile.json" >/dev/null
    sing-box check -D "$TMPDIR" -c "$TMPDIR/zero-naive-profile.json"

    mkdir -p "$out"
    cp "$TMPDIR/mihomo.yaml" "$out/mihomo.yaml"
    cp "$TMPDIR/profile.json" "$out/profile.json"
    cp "$TMPDIR/zero-naive-profile.json" "$out/zero-naive-profile.json"
  ''
