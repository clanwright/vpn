{
  inputs,
  root,
}:
let
  declaredInputs = (import (root + /flake.nix)).inputs;
  lock = builtins.fromJSON (builtins.readFile (root + /flake.lock));
  clanNode = lock.nodes.${lock.nodes.${lock.root}.inputs.clan-core};
  dataMesherNode = lock.nodes.${clanNode.inputs.data-mesher};
  clanLock = builtins.fromJSON (builtins.readFile (inputs.clan-core.outPath + "/flake.lock"));
  bundledNode = clanLock.nodes.${clanLock.nodes.${clanLock.root}.inputs.data-mesher};
  dataMesher = inputs.clan-core.inputs.data-mesher;
  nativeModule = dataMesher.nixosModules.data-mesher;
in
{
  rootDoesNotOverrideDataMesher =
    !(declaredInputs ? data-mesher)
    && !(declaredInputs.clan-core.inputs ? data-mesher)
    && !(lock.nodes.${lock.root}.inputs ? data-mesher);
  clanBundledSourcePreserved =
    dataMesherNode.locked == bundledNode.locked
    && dataMesherNode.original == bundledNode.original
    && dataMesher.rev == bundledNode.locked.rev
    && dataMesher.narHash == bundledNode.locked.narHash;
  clanDependencyFollowsPreserved =
    builtins.all
      (
        name:
        dataMesherNode.inputs.${name} == [
          "clan-core"
          name
        ]
      )
      [
        "flake-parts"
        "nixpkgs"
        "treefmt-nix"
      ];
  nativeModuleExportPreserved =
    nativeModule._class == "nixos"
    && nativeModule._file == "${dataMesher.outPath}/flake.nix#nixosModules.data-mesher"
    && nativeModule.imports != [ ];
}
