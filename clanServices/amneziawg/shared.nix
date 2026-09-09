{ config, lib, ... }:
{
  options.clanwright.vpn.amneziawg = {
    interfaceClaims = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      internal = true;
      description = "Active AmneziaWG interfaces claimed on this machine.";
    };

    listenPortClaims = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      internal = true;
      description = "Active wildcard UDP listen ports claimed by AmneziaWG userspace processes.";
    };

    forwardingRequired = lib.mkOption {
      type = lib.types.boolByOr;
      default = false;
      internal = true;
      description = "Whether an active AmneziaWG instance requires shared IPv4 forwarding.";
    };
  };

  config.boot.kernel.sysctl."net.ipv4.ip_forward" =
    lib.mkIf config.clanwright.vpn.amneziawg.forwardingRequired 1;
}
