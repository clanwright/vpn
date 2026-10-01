# Pinned Clan unconditionally imports this export. It supplies no options,
# package, wrapper or runtime support; it is only an empty NixOS module.
{
  outputs = _: {
    nixosModules.data-mesher = _: { };
  };
}
