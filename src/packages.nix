# WARNING: This file is auto-generated, all modifications may disappear without notice.
{ name ? "nixy-env", packagesJSON ? ./packages.json
, sourcesJSON ? ./sources.json }: rec {
  getName = x:
    let parse = drv: (builtins.parseDrvName drv).name;
    in if builtins.isString x then parse x else x.pname or (parse x.name);

  fetchers = {
    github = spec: builtins.fetchTarball { inherit (spec) sha256 url; };
  };

  mkSource = name: spec: fetchers."${spec.type}" (pp spec);
  sources = builtins.mapAttrs mkSource
    (builtins.fromJSON (builtins.readFile sourcesJSON)).sources;

  pp = v: __trace (__toJSON v) v;

  inherit (nixpkgs) buildEnv lib;
  inherit (lib) splitString getAttrFromPath;

  nixpkgs = import sources.nixpkgs {
    overlays = import ./overlays.nix { inherit sources; };
  };

  paths = map (name:
    let path = splitString "." name;
    in getAttrFromPath path nixpkgs)
    (builtins.fromJSON (builtins.readFile packagesJSON)).packages;

  listing = map (pkg: {
    name = getName pkg;
    description = pkg.meta.description or null;
  }) paths;

  profile = buildEnv {
    inherit name;
    extraOutputsToInstall = [ "out" "bin" "lib" ];
    inherit paths;
  };
}
