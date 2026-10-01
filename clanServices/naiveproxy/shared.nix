{ config, lib, ... }:
{
  options.clanwright.vpn.naiveproxy = {
    connectRouteContent = lib.mkOption {
      type = lib.types.lines;
      default = "";
      internal = true;
      description = "Private source for the singleton authenticated CONNECT fragment.";
    };
    connectRoute = lib.mkOption {
      type = lib.types.lines;
      # Native readOnly counts definitions before priority merging. One shared
      # computed default keeps disabled instances from adding a second definition.
      default = config.clanwright.vpn.naiveproxy.connectRouteContent;
      readOnly = true;
      description = "Complete authenticated CONNECT fragment scoped to the selected public IPv4 listener on local port 443. Naive attaches it once to the selected catch-all; consumers also attach this exact fragment at lib.mkBefore priority 500 inside every selected canonical/alias Host route sharing that public listener, before terminal cover content. Inner ordering does not change native outer Host routing. Private and disjoint listeners are not supported by copying the fragment.";
    };
    activeInstances = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      internal = true;
      description = "Active NaiveProxy instances claiming the machine-wide Caddy forward-proxy integration.";
    };
  };
}
