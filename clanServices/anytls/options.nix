{ lib, ... }:
{
  options.clanwright.vpn.anytls.activeInstances = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    internal = true;
    description = "Active AnyTLS instances claiming the singleton runtime.";
  };
}
