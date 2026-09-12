{
  inputs,
  pkgs,
  root,
  self,
  system ? pkgs.system,
}:
let
  lib = inputs.nixpkgs.lib;
  validation = import ../clanServices/amneziawg/validation.nix { inherit lib; };
  service = import ../clanServices/amneziawg/default.nix {
    inherit lib;
    appsPkgsFor = _: self.packages.${system};
  };
  interface = service.roles.gateway.interface { inherit lib; };
  baseSettings = {
    enable = true;
    interfaceName = "awg-fixture";
    listenIPv4 = "192.0.2.12";
    endpointDomain = "awg.example.invalid";
    listenPort = 443;
    address = "10.77.0.1/24";
    privateKeySecretName = "fixture/awg-private-key";
    headerProtectionKeySecretName = "fixture/awg-header-protection-key";
    serverPublicKey = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    peers = [
      {
        name = "probe";
        publicKey = "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCA=";
        clientPrivateKeySecretName = "consumer/arbitrary-probe-private-key";
        allowedIPs = [ "10.77.0.2/32" ];
        clientPersistentKeepalive = 25;
      }
    ];
    egressIPv4 = "192.0.2.12";
    clientSubnetIPv4 = "10.77.0.0/24";
    enableNat = true;
  };
  secondSettings = baseSettings // {
    interfaceName = "awg-second";
    listenIPv4 = "192.0.2.13";
    listenPort = 8443;
    address = "10.78.0.1/24";
    privateKeySecretName = "fixture/awg-second-private-key";
    headerProtectionKeySecretName = "fixture/awg-second-header-protection-key";
    peers = [
      {
        name = "second";
        publicKey = "MjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjI=";
        clientPrivateKeySecretName = "consumer/arbitrary-second-private-key";
        allowedIPs = [ "10.78.0.2/32" ];
        clientPersistentKeepalive = null;
      }
    ];
    egressIPv4 = "192.0.2.13";
    clientSubnetIPv4 = "10.78.0.0/24";
  };
  fourPeerSettings = baseSettings // {
    peers = [
      (builtins.head baseSettings.peers)
      {
        name = "second";
        publicKey = "DCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCA=";
        clientPrivateKeySecretName = "consumer/second-private-key";
        allowedIPs = [ "10.77.0.3/32" ];
        clientPersistentKeepalive = null;
      }
      {
        name = "third";
        publicKey = "ECCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCA=";
        clientPrivateKeySecretName = "consumer/third-private-key";
        allowedIPs = [ "10.77.0.4/32" ];
        clientPersistentKeepalive = null;
      }
      {
        name = "fourth";
        publicKey = "FCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCA=";
        clientPrivateKeySecretName = "consumer/fourth-private-key";
        allowedIPs = [ "10.77.0.5/32" ];
        clientPersistentKeepalive = null;
      }
    ];
  };
  evalSettings =
    value:
    (lib.evalModules {
      modules = [
        interface
        { config = value; }
      ];
    }).config;
  schemaAccepts = value: (builtins.tryEval (builtins.deepSeq (evalSettings value) true)).success;
  assertionsPass =
    value:
    builtins.all (entry: entry.assertion) (
      validation.assertions {
        settings = evalSettings value;
        serviceName = "amneziawg";
      }
    );
  settings = evalSettings baseSettings;
  instance = service.roles.gateway.perInstance {
    inherit settings;
    instanceName = "fixture--amneziawg";
    machine.name = "fixture";
  };
  provider = instance.exports.vpnProvider;
  metadata = provider.transportMetadata;
  consumer = import ./lib/consumer.nix { inherit inputs root self; };
  consumerResult = consumer { instanceNames = [ "vpn-amneziawg" ]; };
  inherit (consumerResult) machine;
  moduleFor =
    moduleSettings: instanceName:
    (service.roles.gateway.perInstance {
      settings = evalSettings moduleSettings;
      inherit instanceName;
      machine.name = "fixture";
    }).nixosModule;
  extraInstanceMachine =
    moduleSettings: instanceName:
    (consumer {
      instanceNames = [ "vpn-amneziawg" ];
      extraModule.imports = [ (moduleFor moduleSettings instanceName) ];
    }).machine;
  isolatedMachine =
    moduleSettings: instanceName:
    (consumer {
      instanceNames = [ ];
      extraModule.imports = [ (moduleFor moduleSettings instanceName) ];
    }).machine;
  extraInstanceAccepted =
    moduleSettings: instanceName:
    (builtins.tryEval (
      builtins.deepSeq (extraInstanceMachine moduleSettings instanceName).system.build.toplevel.drvPath true
    )).success;
  secondMachine = extraInstanceMachine secondSettings "fixture--amneziawg-second";
  secondUnit = secondMachine.systemd.services."wireguard-awg-second";
  fourPeerMachine = isolatedMachine fourPeerSettings "fixture--amneziawg-four-peers";
  fourPeerPostStart = fourPeerMachine.systemd.services."wireguard-awg-fixture".postStart;
  noNatMachine = isolatedMachine (baseSettings // { enableNat = false; }) "fixture--amneziawg-no-nat";
  disabledMachine = isolatedMachine (
    baseSettings // { enable = false; }
  ) "fixture--amneziawg-disabled";
  forwardingNotRequested =
    evaluatedMachine:
    !evaluatedMachine.clanwright.vpn.amneziawg.forwardingRequired
    && !(evaluatedMachine.boot.kernel.sysctl ? "net.ipv4.ip_forward");
  firewallConfigRejected =
    extraModule:
    !(builtins.tryEval (
      builtins.deepSeq
        (consumer {
          instanceNames = [ "vpn-amneziawg" ];
          inherit extraModule;
        }).machine.system.build.toplevel.drvPath
        true
    )).success;
  unit = machine.systemd.services."wireguard-awg-fixture";
  inherit (unit) postStart;
  beforeLinkUp = builtins.head (lib.splitString "ip link set up dev awg-fixture" postStart);
  secretConfig = machine.sops.secrets;

  invalidContracts =
    !(assertionsPass (baseSettings // { listenIPv4 = "192.0.2.999"; }))
    && !(assertionsPass (baseSettings // { listenIPv4 = "0.0.0.0"; }))
    && !(assertionsPass (baseSettings // { endpointDomain = "invalid domain"; }))
    && !(assertionsPass (baseSettings // { endpointDomain = "invalid..domain"; }))
    && !(assertionsPass (baseSettings // { address = "10.77.0.999/24"; }))
    && !(schemaAccepts (baseSettings // { headerProtectionKeySecretName = "../secret"; }))
    && !(assertionsPass (
      baseSettings
      // {
        headerProtectionKeySecretName = baseSettings.privateKeySecretName;
      }
    ))
    && !(assertionsPass (baseSettings // { serverPublicKey = "not-a-key"; }))
    && !(schemaAccepts (
      baseSettings
      // {
        peers = [
          (builtins.removeAttrs (builtins.head baseSettings.peers) [ "clientPrivateKeySecretName" ])
        ];
      }
    ))
    && !(schemaAccepts (
      baseSettings
      // {
        peers = [
          ((builtins.head baseSettings.peers) // { clientPrivateKeySecretName = "../secret"; })
        ];
      }
    ))
    && !(assertionsPass (
      baseSettings
      // {
        peers = [
          (
            (builtins.head baseSettings.peers)
            // {
              clientPrivateKeySecretName = baseSettings.privateKeySecretName;
            }
          )
        ];
      }
    ))
    && !(assertionsPass (
      baseSettings
      // {
        peers = [
          (
            (builtins.head baseSettings.peers)
            // {
              clientPrivateKeySecretName = baseSettings.headerProtectionKeySecretName;
            }
          )
        ];
      }
    ))
    && !(assertionsPass (
      baseSettings
      // {
        peers = baseSettings.peers ++ [
          {
            name = "second";
            publicKey = "DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDA=";
            clientPrivateKeySecretName = "consumer/arbitrary-probe-private-key";
            allowedIPs = [ "10.77.0.3/32" ];
            clientPersistentKeepalive = null;
          }
        ];
      }
    ))
    && !(assertionsPass (
      baseSettings
      // {
        peers = [
          ((builtins.head baseSettings.peers) // { allowedIPs = [ ]; })
        ];
      }
    ))
    && !(assertionsPass (
      baseSettings
      // {
        peers = baseSettings.peers ++ [ (builtins.head baseSettings.peers) ];
      }
    ))
    && !(assertionsPass (
      baseSettings
      // {
        peers = [
          (builtins.head baseSettings.peers)
          {
            name = "second";
            publicKey = "DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDA=";
            clientPrivateKeySecretName = "consumer/second-private-key";
            allowedIPs = [ "10.77.0.2/32" ];
            clientPersistentKeepalive = null;
          }
        ];
      }
    ))
    && !(assertionsPass (
      baseSettings
      // {
        address = "10.78.0.1/24";
        enableNat = false;
      }
    ))
    && !(assertionsPass (
      baseSettings
      // {
        clientSubnetIPv4 = "10.77.0.0/25";
      }
    ))
    && !(assertionsPass (
      baseSettings
      // {
        peers = [
          ((builtins.head baseSettings.peers) // { allowedIPs = [ "10.77.0.2/31" ]; })
          {
            name = "second";
            publicKey = "DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDA=";
            clientPrivateKeySecretName = "consumer/second-private-key";
            allowedIPs = [ "10.77.0.3/32" ];
            clientPersistentKeepalive = null;
          }
        ];
      }
    ))
    && !(assertionsPass (
      baseSettings
      // {
        peers = [
          (
            (builtins.head baseSettings.peers)
            // {
              allowedIPs = [
                "10.77.0.2/32"
                "10.77.0.3/32"
              ];
            }
          )
        ];
      }
    ))
    && !(assertionsPass (
      baseSettings
      // {
        peers = [
          ((builtins.head baseSettings.peers) // { allowedIPs = [ "10.78.0.2/32" ]; })
        ];
      }
    ))
    && !(assertionsPass (
      baseSettings
      // {
        peers = [
          ((builtins.head baseSettings.peers) // { allowedIPs = [ "10.77.0.1/32" ]; })
        ];
      }
    ))
    && !(assertionsPass (
      baseSettings
      // {
        peers = [
          ((builtins.head baseSettings.peers) // { allowedIPs = [ "010.77.0.2/32" ]; })
        ];
      }
    ))
    && !(assertionsPass (
      baseSettings
      // {
        peers = [
          ((builtins.head baseSettings.peers) // { allowedIPs = [ "10.77.0.2/032" ]; })
        ];
      }
    ))
    && !(schemaAccepts (baseSettings // { mtu = 1280; }))
    && !(schemaAccepts (
      baseSettings
      // {
        extraOptions = {
          S1 = 56;
        };
      }
    ))
    && !(schemaAccepts (baseSettings // { serverPersistentKeepalive = 25; }));

  exportContract =
    provider.schemaVersion == 2
    && provider.secretNames.headerProtectionKey == "fixture/awg-header-protection-key"
    && provider.secretNames.clientPrivateKey.probe == "consumer/arbitrary-probe-private-key"
    && metadata.generation == 3
    && metadata.profile == validation.profile
    && metadata.mtu == 1280
    && !(metadata ? headerProtectionKey)
    && !(metadata ? peerPublicKeys)
    && !(builtins.head metadata.peers ? clientPrivateKeySecretName)
    && !(metadata ? extraOptions)
    &&
      validation.profile == {
        s1 = 12;
        s2 = 12;
        s3 = 12;
        s4 = 12;
        h1 = 1;
        h2 = 2;
        h3 = 3;
        h4 = 4;
        contentPaddingAddition = {
          min = 2;
          max = 10;
        };
        randomTrailers = true;
        disableCookies = false;
      };

  runtimeConfigContract =
    assertionsPass baseSettings
    && !(machine.networking.wireguard.interfaces ? awg-fixture)
    && unit.serviceConfig.Type == "exec"
    &&
      unit.serviceConfig.ExecStart
      == "${self.packages.${system}.amneziawg-go}/bin/amneziawg-go -f awg-fixture"
    && unit.serviceConfig.Restart == "on-failure"
    && unit.serviceConfig.RestartSec == "5s"
    && unit.serviceConfig.TimeoutStartSec == "20s"
    &&
      unit.serviceConfig.AmbientCapabilities == [
        "CAP_NET_ADMIN"
        "CAP_NET_BIND_SERVICE"
      ]
    &&
      unit.serviceConfig.CapabilityBoundingSet == [
        "CAP_NET_ADMIN"
        "CAP_NET_BIND_SERVICE"
      ]
    && unit.serviceConfig.DeviceAllow == [ "/dev/net/tun rw" ]
    && unit.serviceConfig.DevicePolicy == "closed"
    && unit.serviceConfig.LockPersonality
    && unit.serviceConfig.NoNewPrivileges
    && unit.serviceConfig.PrivateTmp
    && unit.serviceConfig.ProtectControlGroups
    && unit.serviceConfig.ProtectHome == true
    && unit.serviceConfig.ProtectKernelModules
    && unit.serviceConfig.ProtectKernelTunables
    && unit.serviceConfig.ProtectSystem == "strict"
    &&
      unit.serviceConfig.RestrictAddressFamilies == [
        "AF_INET"
        "AF_INET6"
        "AF_NETLINK"
        "AF_UNIX"
      ]
    && builtins.all (name: !(lib.hasInfix name postStart)) [
      " jc "
      " i1 "
      " i2 "
      " i3 "
      " i4 "
      " i5 "
      " rekey-after-time "
      " rekey-timeout "
      " reject-after-time "
      " keepalive-timeout "
      " max-handshake-attempts "
      " persistent-keepalive "
    ]
    && lib.hasInfix "header-protection-key /run/secrets/fixture-awg-header-protection-key" beforeLinkUp
    && !(lib.hasInfix "header-protection-key" (
      builtins.elemAt (lib.splitString "ip link set up dev awg-fixture" postStart) 1
    ))
    && lib.hasInfix "private-key /run/secrets/fixture-awg-server-private-key" beforeLinkUp
    && lib.hasInfix "content-padding-addition 2-10" beforeLinkUp
    && lib.hasInfix "random-trailers on" beforeLinkUp
    && lib.hasInfix "disable-cookies off" beforeLinkUp
    && lib.hasInfix "ip address add 10.77.0.1/24 dev awg-fixture" postStart
    && lib.hasInfix "ip route replace 10.77.0.2/32 dev awg-fixture" postStart
    && lib.hasInfix "ip -o link show dev awg-fixture up 2>/dev/null" postStart
    && lib.hasInfix "awg show interfaces" postStart
    && lib.hasInfix "awg show awg-fixture listen-port" postStart
    && lib.hasInfix "awg show awg-fixture peers" postStart
    && lib.hasInfix "awg show awg-fixture allowed-ips" postStart
    && builtins.all (unsafe: !(lib.hasInfix unsafe postStart)) [
      "awg show awg-fixture dump"
      "awg showconf awg-fixture"
      "awg show awg-fixture private-key"
      "WG_HIDE_KEYS=never"
    ]
    && lib.hasInfix "interface readiness query failed\" >&2\n  exit 1" postStart
    && lib.hasInfix "listen-port readiness query failed\" >&2\n  exit 1" postStart
    && lib.hasInfix "peer readiness query failed\" >&2\n  exit 1" postStart
    && lib.hasInfix "allowed-ips readiness query failed\" >&2\n  exit 1" postStart
    && lib.hasInfix "LC_ALL=C" postStart
    && !(lib.hasInfix "modprobe amneziawg" postStart)
    && !(lib.hasInfix "link add dev" postStart)
    && builtins.length (lib.toList unit.serviceConfig.ExecStopPost) == 1
    && lib.hasSuffix "/bin/wireguard-awg-fixture-post-stop" (
      builtins.head (lib.toList unit.serviceConfig.ExecStopPost)
    )
    && lib.hasInfix "ip link delete dev awg-fixture" unit.postStop
    && lib.hasInfix "rm -f -- /run/amneziawg/awg-fixture.sock" unit.postStop
    && !(lib.hasInfix "<SOPS:" postStart)
    && (
      if machine.sops.useSystemdActivation then
        builtins.elem "sops-install-secrets.service" unit.after
        && builtins.elem "sops-install-secrets.service" unit.wants
      else
        !(builtins.elem "sops-install-secrets.service" unit.after)
        && !(builtins.elem "sops-install-secrets.service" unit.wants)
    )
    && secretConfig.fixture-awg-server-private-key.mode == "0400"
    && secretConfig.fixture-awg-header-protection-key.mode == "0400"
    && secretConfig.fixture-awg-server-private-key.restartUnits == [ "wireguard-awg-fixture.service" ]
    &&
      secretConfig.fixture-awg-header-protection-key.restartUnits == [ "wireguard-awg-fixture.service" ];

  fourPeerRuntimeContract =
    assertionsPass fourPeerSettings
    && builtins.all (fragment: lib.hasInfix fragment fourPeerPostStart) [
      "peer 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCA=' allowed-ips 10.77.0.2/32"
      "peer 'DCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCA=' allowed-ips 10.77.0.3/32"
      "peer 'ECCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCA=' allowed-ips 10.77.0.4/32"
      "peer 'FCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCA=' allowed-ips 10.77.0.5/32"
    ]
    && !(lib.hasInfix "allowed-ips 10.77.0.2/32\n" fourPeerPostStart)
    && lib.hasInfix "10.77.0.2/32 peer 'DCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCA='" fourPeerPostStart
    && lib.hasInfix "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCA=\nDCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCA=" fourPeerPostStart
    && lib.hasInfix "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCA=\t10.77.0.2/32" fourPeerPostStart
    && lib.hasInfix "while [ ! -S /run/amneziawg/awg-fixture.sock ] && [ \"$attempts\" -lt 100 ]; do" fourPeerPostStart
    && lib.hasInfix "if [ ! -S /run/amneziawg/awg-fixture.sock ]; then" fourPeerPostStart
    && lib.hasInfix "userspace interface socket did not become ready\" >&2\n  exit 1" fourPeerPostStart
    && lib.hasInfix "if ! /nix/store/" fourPeerPostStart
    && lib.hasInfix "/bin/awg set awg-fixture" fourPeerPostStart
    && builtins.length (lib.splitString "/bin/awg set " fourPeerPostStart) == 2
    && lib.hasInfix ">/dev/null 2>&1; then\n  echo \"amneziawg: userspace interface configuration failed" fourPeerPostStart
    && lib.hasInfix "amneziawg: userspace interface configuration failed\" >&2\n  exit 1" fourPeerPostStart;

  firewallContract =
    lib.hasInfix "ip daddr 192.0.2.12 udp dport 443 accept" machine.networking.firewall.extraInputRules
    &&
      lib.hasInfix "ip saddr 10.77.0.0/24 ip daddr != 10.77.0.0/24 snat to 192.0.2.12"
        machine.networking.nftables.tables.${"vpn_amneziawg_${builtins.hashString "sha256" "awg-fixture"}"}.content
    && !(builtins.elem 443 machine.networking.firewall.allowedUDPPorts)
    && firewallConfigRejected { networking.firewall.enable = lib.mkForce false; }
    && firewallConfigRejected { networking.firewall.backend = lib.mkForce "iptables"; };

  interfaceClaimResults = {
    duplicateInterfaceRejected = !(extraInstanceAccepted baseSettings "fixture--amneziawg-duplicate");
    duplicatePortRejected =
      !(extraInstanceAccepted (
        secondSettings // { inherit (baseSettings) listenPort; }
      ) "fixture--amneziawg-same-port");
    distinctAccepted = extraInstanceAccepted secondSettings "fixture--amneziawg-second";
    ambientCapabilities = secondUnit.serviceConfig.AmbientCapabilities == [ "CAP_NET_ADMIN" ];
    capabilityBoundingSet = secondUnit.serviceConfig.CapabilityBoundingSet == [ "CAP_NET_ADMIN" ];
    forwardingEnabled = secondMachine.boot.kernel.sysctl."net.ipv4.ip_forward" == 1;
    noNatForwardingDisabled = forwardingNotRequested noNatMachine;
    disabledForwardingDisabled = forwardingNotRequested disabledMachine;
  };
  interfaceClaimContract = builtins.all (value: value) (builtins.attrValues interfaceClaimResults);

  disabledContract =
    !(disabledMachine.systemd.services ? "wireguard-awg-fixture")
    && !(disabledMachine.sops.secrets ? "fixture/awg-private-key")
    && !(disabledMachine.sops.secrets ? "fixture/awg-header-protection-key")
    && !(
      disabledMachine.networking.nftables.tables
      ? ${"vpn_amneziawg_${builtins.hashString "sha256" "awg-fixture"}"}
    );

  dottedIdentityContract = schemaAccepts (
    baseSettings
    // {
      peers = map (peer: peer // { name = "device.${peer.name}"; }) baseSettings.peers;
    }
  );

  contract =
    invalidContracts
    && dottedIdentityContract
    && exportContract
    && runtimeConfigContract
    && fourPeerRuntimeContract
    && firewallContract
    && interfaceClaimContract
    && disabledContract;
in
if !contract then
  throw "AWG3 validation, export, fail-closed readiness, cleanup, or firewall contract failed: ${
    builtins.toJSON {
      inherit
        disabledContract
        dottedIdentityContract
        exportContract
        firewallContract
        fourPeerRuntimeContract
        interfaceClaimContract
        interfaceClaimResults
        invalidContracts
        runtimeConfigContract
        ;
    }
  }"
else
  { all = true; }
