{ lib, ... }:
{
  options.clanwright.dns.unbound.activeInstances = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    internal = true;
    description = "Active Unbound instances claiming the native recursive resolver runtime.";
  };
}
