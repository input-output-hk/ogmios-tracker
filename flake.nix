{
  inputs.nixpkgs-2305.url = "github:NixOS/nixpkgs/nixos-23.05";

  inputs.flake-compat.url = "github:input-output-hk/flake-compat";
  inputs.flake-compat.flake = false;

  outputs = inputs: let
    matrix = [
      # ogmiosRef                                   ogmiosHash                                             nodeRef      nodeHash
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

              packages.bech32.components.library.pkgconfig = [[pkgs.libblst]];
              packages.bech32-th.components.library.pkgconfig = [[pkgs.libblst]];
              packages.byron-spec-chain.components.library.pkgconfig = [[pkgs.libblst]];
              packages.byron-spec-ledger.components.library.pkgconfig = [[pkgs.libblst]];
              packages.cardano-binary.components.library.pkgconfig = [[pkgs.libblst]];
              packages.cardano-crypto.components.library.pkgconfig = [[pkgs.libblst]];
              packages.cardano-crypto-test.components.library.pkgconfig = [[pkgs.libblst]];
              packages.cardano-crypto-tests.components.library.pkgconfig = [[pkgs.libblst]];
              packages.cardano-crypto-wrapper.components.library.pkgconfig = [[pkgs.libblst]];
              packages.cardano-data.components.library.pkgconfig = [[pkgs.libblst]];
              packages.cardano-ledger-allegra.components.library.pkgconfig = [[pkgs.libblst]];
              packages.cardano-ledger-alonzo.components.library.pkgconfig = [[pkgs.libblst]];
              packages.cardano-ledger-alonzo-test.components.library.pkgconfig = [[pkgs.libblst]];
              packages.cardano-ledger-api.components.library.pkgconfig = [[pkgs.libblst]];
              packages.cardano-ledger-babbage.components.library.pkgconfig = [[pkgs.libblst]];
              packages.cardano-ledger-babbage-test.components.library.pkgconfig = [[pkgs.libblst]];
              packages.cardano-ledger-binary.components.library.pkgconfig = [[pkgs.libblst]];
              packages.cardano-ledger-byron.components.library.pkgconfig = [[pkgs.libblst]];
              packages.cardano-ledger-byron-test.components.library.pkgconfig = [[pkgs.libblst]];
              packages.cardano-ledger-conway.components.library.pkgconfig = [[pkgs.libblst]];
              packages.cardano-ledger-conway-test.components.library.pkgconfig = [[pkgs.libblst]];
              packages.cardano-ledger-core.components.library.pkgconfig = [[pkgs.libblst]];
              packages.cardano-ledger-mary.components.library.pkgconfig = [[pkgs.libblst]];
              packages.cardano-ledger-pretty.components.library.pkgconfig = [[pkgs.libblst]];
              packages.cardano-ledger-shelley.components.library.pkgconfig = [[pkgs.libblst]];
              packages.cardano-ledger-shelley-ma-test.components.library.pkgconfig = [[pkgs.libblst]];
              packages.cardano-ledger-shelley-test.components.library.pkgconfig = [[pkgs.libblst]];
              packages.cardano-prelude.components.library.pkgconfig = [[pkgs.libblst]];
              packages.cardano-prelude-test.components.library.pkgconfig = [[pkgs.libblst]];
              packages.cardano-protocol-tpraos.components.library.pkgconfig = [[pkgs.libblst]];
              packages.cardano-slotting.components.library.pkgconfig = [[pkgs.libblst]];
              packages.cardano-strict-containers.components.library.pkgconfig = [[pkgs.libblst]];
              packages.fast-bech32.components.library.pkgconfig = [[pkgs.libblst]];
              packages.ogmios.components.library.pkgconfig = [[pkgs.libblst]];
              packages.ouroboros-consensus.components.library.pkgconfig = [[pkgs.libblst]];
              packages.ouroboros-consensus-cardano.components.library.pkgconfig = [[pkgs.libblst]];
              packages.ouroboros-consensus-diffusion.components.library.pkgconfig = [[pkgs.libblst]];
              packages.ouroboros-consensus-protocol.components.library.pkgconfig = [[pkgs.libblst]];
              packages.ouroboros-network.components.library.pkgconfig = [[pkgs.libblst]];
              packages.ouroboros-network-api.components.library.pkgconfig = [[pkgs.libblst]];
              packages.ouroboros-network-framework.components.library.pkgconfig = [[pkgs.libblst]];
              packages.ouroboros-network-mock.components.library.pkgconfig = [[pkgs.libblst]];
              packages.ouroboros-network-ogmios.components.library.pkgconfig = [[pkgs.libblst]];
              packages.ouroboros-network-protocols.components.library.pkgconfig = [[pkgs.libblst]];
              packages.ouroboros-network-testing.components.library.pkgconfig = [[pkgs.libblst]];
              packages.plutus-core.components.library.pkgconfig = [[pkgs.libblst]];
              packages.plutus-ledger-api.components.library.pkgconfig = [[pkgs.libblst]];
              packages.plutus-tx.components.library.pkgconfig = [[pkgs.libblst]];

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
