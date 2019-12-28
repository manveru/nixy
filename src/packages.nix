# WARNING: This file is auto-generated, all modifications may disappear without notice.
{ pkgs ? import ~/nixos-conf/nix { }, name ? "nixy-env"
, packagesJSON ? ./packages.json }: rec {
  paths = map (name:
    let path = pkgs.lib.splitString "." name;
    in pkgs.lib.getAttrFromPath path pkgs)
    (builtins.fromJSON (builtins.readFile packagesJSON)).packages;

  listing = map (pkg: {
    name = pkgs.lib.getName pkg;
    description = pkg.meta.description or null;
  }) paths;

  profile = pkgs.buildEnv {
    inherit name;
    extraOutputsToInstall = [ "out" "bin" "lib" ];
    inherit paths;
  };
}
