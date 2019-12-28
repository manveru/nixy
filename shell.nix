with import ./nix {}; mkShell {
  buildInputs = [ niv crystal readline ];
}
