with import ./nix {};
let
  inherit (lib) any;
  # NOTE: find a way to handle duplicates better, atm they may override each
  # other without warning
  mkWhiteList = allowedPaths:
    lib.foldl' (sum: allowed:
      if (lib.pathIsDirectory allowed) then {
        tree = lib.recursiveUpdate sum.tree
          (lib.setAttrByPath (pathToParts allowed) true);
        prefixes = sum.prefixes ++ [ (toString allowed) ];
      } else {
        tree = lib.recursiveUpdate sum.tree
          (lib.setAttrByPath (pathToParts allowed) false);
        prefixes = sum.prefixes;
      }) {
        tree = { };
        prefixes = [ ];
      } allowedPaths;

  pathToParts = path: (__tail (lib.splitString "/" (toString path)));

  isWhiteListed = patterns: name: type:
    let
      parts = pathToParts name;
      matchesTree = lib.hasAttrByPath parts patterns.tree;
      matchesPrefix = lib.any (pre: lib.hasPrefix pre name) patterns.prefixes;
    in matchesTree || matchesPrefix;

  whiteList = root: allowedPaths:
    let
      patterns = mkWhiteList allowedPaths;
      filter = isWhiteListed patterns;
    in __filterSource filter root;

  mypkgs = import ~/github/nixos/nixpkgs {};
  crystal = mypkgs.crystal_0_30;

in crystal.buildCrystalPackage {
  name = "nixy";
  version = "0.1.1";
  src = whiteList ./. [ ./src ];

  buildInputs = [ readline ];

  shardsFile = ./shards.nix;

  crystalBinaries.nixy.src = "src/nixy.cr";
}
