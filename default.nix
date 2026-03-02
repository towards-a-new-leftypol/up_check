{ pkgs ? import <nixpkgs> {}, }:

let
  haskell = pkgs.haskell.packages.ghc912;

  drv = haskell.callCabal2nix "up-check" ./. {
  };

  env = drv.env.overrideAttrs (oldAttrs: {
    buildInputs = oldAttrs.buildInputs ++ [
      pkgs.haskellPackages.cabal-install
      haskell.miso-from-html
      haskell.hlint
      haskell.haskell-language-server
    ];
  });

in

if pkgs.lib.inNixShell then env else drv
