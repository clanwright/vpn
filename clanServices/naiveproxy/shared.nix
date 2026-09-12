{ lib, ... }:
{
  options.clanwright.vpn.naiveproxy.activeInstances = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    internal = true;
    description = "Active NaiveProxy instances claiming the machine-wide Caddy forward-proxy integration.";
  };
}
