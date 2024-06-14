{
  description = "ibizaman's blog";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    hakyll-flakes.url = "github:Radvendii/hakyll-flakes";
    flake-utils.url = "github:numtide/flake-utils";
    flake-compat.url = "https://flakehub.com/f/edolstra/flake-compat/1.tar.gz";
  };

  outputs = { nixpkgs, hakyll-flakes, flake-utils, ... }:
    let
      supportedSystems = [
        "x86_64-linux"
        "x86_64-darwin"
        "aarch64-linux"
        "aarch64-darwin"
      ];
    in
      flake-utils.lib.eachSystem supportedSystems (system:
        # nix run . watch
        hakyll-flakes.lib.mkAllOutputs {
          inherit system;
          name = "site";
          src = ./.;
          websiteBuildInputs = with nixpkgs.legacyPackages.${system}; [
            cabal-install
            haskell-language-server
            # rubber
            # texlive.combined.scheme-full
            # poppler_utils
          ];
        });
}
