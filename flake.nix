{
  inputs.nixpkgs-2305.url = "github:NixOS/nixpkgs/nixos-23.05";

  inputs.flake-compat.url = "github:input-output-hk/flake-compat";
  inputs.flake-compat.flake = false;

  outputs = inputs: let
    matrix = [
      # ogmiosRef                                   ogmiosHash                                             nodeRef      nodeHash
      [ "v5.6.0"                                    "sha256-7Hb/ZaEnnMSOPhRlx4YR+cgpZOttYEJNzHBl+RamlZM="  "1.35.5"     "sha256-LwoQejDDA9P7dbl8z3nFbEJDDim0Y7oHUOgf4EH2Xig=" ]
      [ "v6.0.0"                                    "sha256-Ikun65xEiChdd6TMC3RYqjRj+w1Lcz1jRMT5W1lm9h0="  "8.1.2"      "sha256-d0V8N+y/OarYv6GQycGXnbPly7GeJRBEeE1017qj9eI=" ]
      [ "f40a8921906fecae4c52ffff34fb011457f9a771"  "sha256-lNe0uK/fH18om8mhMx9jZ2zAQT47u5zNtjU+ZXoUzBY="  "8.1.2"      "sha256-d0V8N+y/OarYv6GQycGXnbPly7GeJRBEeE1017qj9eI=" ]
      [ "f40a8921906fecae4c52ffff34fb011457f9a771"  "sha256-lNe0uK/fH18om8mhMx9jZ2zAQT47u5zNtjU+ZXoUzBY="  "8.3.1-pre"  "sha256-64Nc6CKSMe4SoOu1zaqP9XekWWMDsTVRAJ5faEvbkb4=" ]
      [ "v6.0.0-rc2"                                "sha256-UWw+sOn6k2iwpRanz2XwuEmrM7pjyuGXn1FU0NSUgCQ="  "8.3.1-pre"  "sha256-64Nc6CKSMe4SoOu1zaqP9XekWWMDsTVRAJ5faEvbkb4=" ]
      [ "f40a8921906fecae4c52ffff34fb011457f9a771"  "sha256-lNe0uK/fH18om8mhMx9jZ2zAQT47u5zNtjU+ZXoUzBY="  "8.4.0-pre"  "sha256-aOedRHY27/Iq+tMuA5DMbqySj2BORRaFWRdPhaajExs=" ]
      [ "2b3370b53384a992a0f81795946d94fc7ce210b9"  "sha256-11WcsfT+DGx+nUmcSBNFWqLciUiIO+h5CH18wM4BBA8="  "8.5.0-pre"  "sha256-ONCnN1fLtYJB9kXDlUbF6nIjTnlqvI7kfppftrOOWAY=" ]
      [ "v6.0.0-rc3"                                "sha256-d7mPDogaA1zkeYhoUSD95Mv0HPVfJFS4jWU4q7l/KTs="  "8.5.0-pre"  "sha256-ONCnN1fLtYJB9kXDlUbF6nIjTnlqvI7kfppftrOOWAY=" ]
    ];
    supportedSystems = [ "x86_64-linux" /*"aarch64-linux"*/ ];
    inherit (inputs.nixpkgs-2305) lib;
  in {

    packages = lib.genAttrs supportedSystems (system: let
      pkgs = inputs.nixpkgs-2305.legacyPackages.${system};

      buildOgmios = ogmiosRef: ogmiosHash: nodeRef: nodeHash:
        null;
    in
      lib.listToAttrs (lib.concatMap (matrixRow:
        assert (lib.length matrixRow == 4);
        let
          ogmiosRef  = lib.elemAt matrixRow 0;
          ogmiosHash = lib.elemAt matrixRow 1;
          nodeRef    = lib.elemAt matrixRow 2;
          nodeHash   = lib.elemAt matrixRow 3;

          ogmiosSrc = pkgs.fetchgit {
            url = "https://github.com/CardanoSolutions/ogmios.git";
            rev = ogmiosRef;
            fetchSubmodules = true;
            hash = ogmiosHash;
          };

          ogmiosPatched = pkgs.runCommandNoCC "ogmios-src" {} ''
            cp -r ${ogmiosSrc} $out
            chmod -R +w $out
            find $out -name cabal.project.freeze -delete -o -name package.yaml -delete
            grep -RF -- -external-libsodium-vrf $out | cut -d: -f1 | sort --uniq | xargs -n1 -- sed -r s/-external-libsodium-vrf//g -i
          '';

          nodeSrc = pkgs.fetchFromGitHub {
            owner = "input-output-hk";
            repo = "cardano-node";
            rev = nodeRef;
            hash = nodeHash;
          };

          nodeFlake = (import inputs.flake-compat { src = nodeSrc; }).defaultNix;

          inherit (nodeFlake.legacyPackages.${system}) haskell-nix;

          ogmiosProject = haskell-nix.project {
            compiler-nix-name = "ghc8107";
            projectFileName = "cabal.project";
            inputMap = { "https://input-output-hk.github.io/cardano-haskell-packages" = nodeFlake.inputs.CHaP; };
            src = ogmiosPatched + "/server";
            modules = [ ({ lib, pkgs, ... }: {
              packages.cardano-crypto-praos.components.library.pkgconfig = lib.mkForce [ [ pkgs.libsodium-vrf ] ];
              packages.cardano-crypto-class.components.library.pkgconfig = lib.mkForce [ ([ pkgs.libsodium-vrf pkgs.secp256k1 ]
                ++ (if pkgs ? libblst then [pkgs.libblst] else [])) ];
            }) ];
          };

          shorten = ref: lib.substring 0 15 ref;
        in
          [
            {
              name = "ogmios-${shorten ogmiosRef}-node-${shorten nodeRef}";
              value = ogmiosProject.hsPkgs.ogmios.components.exes.ogmios;
            }
            {
              name = "ogmios-${shorten ogmiosRef}-node-${shorten nodeRef}-static";
              value = ogmiosProject.projectCross.${{
                x86_64-linux = "musl64";
                aarch64-linux = "aarch64-multiplatform-musl";
              }.${system}}.hsPkgs.ogmios.components.exes.ogmios;
            }
          ]
      ) matrix)
    );

    hydraJobs = inputs.self.packages // {
      required = inputs.nixpkgs-2305.legacyPackages.x86_64-linux.releaseTools.aggregate {
        name = "github-required";
        meta.description = "All jobs required to pass CI";
        constituents = lib.collect lib.isDerivation inputs.self.packages;
      };
    };
  };
}
