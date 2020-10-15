# https://robertwpearce.com/hakyll-pt-6-pure-builds-with-nix.html
{ compiler ? "ghc883"
, pkgs ? import <nixpkgs> {}
}:

let
  inherit (pkgs.lib.trivial) flip pipe;
  inherit (pkgs.haskell.lib) appendPatch appendConfigureFlags;

  haskellPackages = pkgs.haskell.packages.${compiler}.override {
    overrides = hpNew: hpOld: {
      hakyll =
        pipe
           hpOld.hakyll
           [ (flip appendPatch ./hakyll.patch)
             (flip appendConfigureFlags [ "-f" "watchServer" "-f" "previewServer" ])
           ];

      # https://www.slamecka.cz/posts/2020-06-08-encoding-issues-with-nix-hakyll/
      hakyll-blog = (hpNew.callCabal2nix "blog" ./. { }).overrideAttrs (old: {
        nativeBuildInputs = old.nativeBuildInputs or [] ++ [
          pkgs.makeWrapper
        ];
        postInstall = old.postInstall or "" + ''
        wrapProgram $out/bin/site \
          --set LANG "en_US.UTF-8" \
          --set LOCALE_ARCHIVE "${pkgs.glibcLocales}/lib/locale/locale-archive"
        '';
      });
    };
  };

  project = haskellPackages.hakyll-blog;
in
{
  project = project;

  shell = haskellPackages.shellFor {
    packages = p: with p; [
      project
    ];
    buildInputs = with haskellPackages; [
      ghcid
      ghcide
      brittany
      hlint
    ];
    withHoogle = true;
  };
}
