{
  inputs = {
    flake-compat = { url = "github:input-output-hk/flake-compat"; flake = false; };
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";

    cardano-node-1-35-5 = { url = "github:IntersectMBO/cardano-node/1.35.5"; flake = false; };
    cardano-node-1-35-7 = { url = "github:IntersectMBO/cardano-node/1.35.7"; flake = false; };
    cardano-node-8-8-0-pre = { url = "github:IntersectMBO/cardano-node/8.8.0-pre"; flake = false; };
    cardano-node-8-9-0 = { url = "github:IntersectMBO/cardano-node/8.9.0"; flake = false; };

    cardano-db-sync-13-1-0-0 = { url = "github:IntersectMBO/cardano-db-sync/13.1.0.0"; flake = false; };
    cardano-db-sync-sancho-4-0-0 = { url = "github:IntersectMBO/cardano-db-sync/sancho-4-0-0"; flake = false; };

    ogmios-5-6-0 = { url = "https://github.com/CardanoSolutions/ogmios.git"; ref = "refs/tags/v5.6.0"; type = "git"; submodules = true; flake = false; };
    ogmios-6-1-0 = { url = "https://github.com/CardanoSolutions/ogmios.git"; ref = "refs/tags/v6.1.0"; type = "git"; submodules = true; flake = false; };
  };

  outputs = inputs: {

    packages.aarch64-linux = let
      system = "aarch64-linux";
      ghRepo = "input-output-hk/ogmios-tracker";
      imagePrefix = "ghcr.io/${ghRepo}/";
      pkgs = inputs.nixpkgs.legacyPackages.${system};
      inherit (pkgs) lib;
      enableAArch64 = { original, supportedSystemsPath, extraPatch ? "" }: let
        patched = pkgs.runCommandNoCC "patched" {} ''
          cp -r ${original} $out
          chmod -R +w $out
          echo ${with pkgs; with lib; escapeShellArg (__toJSON [system])} >$out/${supportedSystemsPath}
          ${extraPatch}
        '';
      in {
        inherit (patched) outPath;
        inherit (original) rev shortRev lastModified lastModifiedDate;
      };
      # Unfortunately, you can’t have slashes in image names in older Nixpkgs, so:
      retagOCI = newName: newTag: original: let
        repo = "input-output-hk/ogmios-tracker";
        namePrefix = "ghcr.io/${repo}/";
        source = "https://github.com/${repo}";
        revision = inputs.self.rev or "dirty";
      in pkgs.runCommand "retagged-${original.name}" {
        buildInputs = with pkgs; [ gnutar jq ];
      } ''
        mkdir unpack && cd unpack
        tar -xzf ${original}
        chmod -R +w .

        oldConfig=$(jq -r '.[0].Config' manifest.json)
        jq \
          --arg source ${pkgs.lib.escapeShellArg source} \
          --arg revision ${pkgs.lib.escapeShellArg revision} \
          '
            .config.Labels."org.opencontainers.image.source" = $source
          | .config.Labels."org.opencontainers.image.revision" = $revision
          ' "$oldConfig" > new-config.json
        newConfig=$(sha256sum new-config.json | cut -d' ' -f1).json
        mv new-config.json "$newConfig"
        rm "$oldConfig"

        jq \
          --arg newTag ${pkgs.lib.escapeShellArg "${namePrefix}${newName}:${newTag}"} \
          --arg newConfig "$newConfig" \
          '.[0].RepoTags[0] = $newTag | .[0].Config = $newConfig' \
          manifest.json >manifest.json.new
        mv manifest.json.new manifest.json

        tar -czf $out .
      '';
    in lib.listToAttrs (

      [{
        name = "all-oci";
        value = pkgs.linkFarm "all-oci" (lib.mapAttrs' (k: v: {
          name = lib.replaceStrings ["--oci"] [""] k + ".tar.gz";
          value = v;
        }) (lib.filterAttrs (k: v: lib.hasInfix "--oci" k) inputs.self.outputs.packages.${system}));
      }]

      ++

      # ——————————————————     ogmios      —————————————————— #

      (let
        input = "ogmios-5-6-0";
        version = builtins.replaceStrings ["refs/tags/v"] [""] (builtins.fromJSON (builtins.readFile ./flake.lock)).nodes.${input}.original.ref;
        patched = pkgs.runCommandNoCC "ogmios-src" {} ''
          cp -r ${inputs.${input}} $out
          chmod -R +w $out
          find $out -name cabal.project.freeze -delete -o -name package.yaml -delete
          grep -RF -- -external-libsodium-vrf $out | cut -d: -f1 | sort --uniq | xargs -n1 -- sed -r s/-external-libsodium-vrf//g -i
        '';
        nodeFlake = inputs.self.outputs.packages.${system}."cardano-node-1-35-5--flake";
        inherit (nodeFlake.legacyPackages.${system}) haskell-nix;
        project = haskell-nix.project {
          compiler-nix-name = "ghc8107";
          projectFileName = "cabal.project";
          inputMap = { "https://input-output-hk.github.io/cardano-haskell-packages" = nodeFlake.inputs.CHaP; };
          src = patched + "/server";
          modules = [ ({ lib, pkgs, ... }: {
            packages.cardano-crypto-praos.components.library.pkgconfig = lib.mkForce [ [ pkgs.libsodium-vrf ] ];
            packages.cardano-crypto-class.components.library.pkgconfig = lib.mkForce [ ([ pkgs.libsodium-vrf pkgs.secp256k1 ]
              ++ (if pkgs ? libblst then [pkgs.libblst] else [])) ];
            packages.ogmios.components.library.preConfigure = "export GIT_SHA=${inputs.${input}.rev}";
          }) ];
        };
        ogmios = project.hsPkgs.ogmios.components.exes.ogmios;
        cardanoConfigurations = pkgs.fetchFromGitHub {
          owner = "input-output-hk";
          repo = "cardano-configurations";
          rev = "c0d11b5ff0c0200da00a50c17c38d9fd752ba532";
          hash = "sha256-oOycxAu9kARfyUvkdjeq80Em7b+vP9XsBii8836f9yQ=";
        };
      in [
        { name = "${input}"; value = ogmios; }
        {
          name = "${input}--oci";
          value = let
            pkgs = nodeFlake.legacyPackages.${system};
          in retagOCI "ogmios" "v${version}" (pkgs.dockerTools.buildImage {
            name = "ogmios";
            tag = "v${version}";
            config = {
              ExposedPorts = {
                "1337/tcp" = {};
              };
              Labels = {
                description = "A JSON WebSocket bridge for cardano-node.";
                name = "ogmios";
              };
              Entrypoint = [ "/bin/ogmios" ];
              StopSignal = "SIGINT";
              Healthcheck = {
                Test = [ "CMD-SHELL" "/bin/ogmios health-check" ];
                Interval = 10000000000;
                Timeout = 5000000000;
                Retries = 1;
              };
            };
            copyToRoot = pkgs.buildEnv {
              name = "ogmios-env";
              paths = [ ogmios ] ++ (with pkgs; [ busybox ]);
              postBuild = ''
                cp -r ${cardanoConfigurations}/network/mainnet $out/config
              '';
            };
          });
        }
      ])

      ++

      (let
        input = "ogmios-6-1-0";
        version = builtins.replaceStrings ["refs/tags/v"] [""] (builtins.fromJSON (builtins.readFile ./flake.lock)).nodes.${input}.original.ref;
        patched = pkgs.runCommandNoCC "ogmios-src" {} ''
          cp -r ${inputs.${input}} $out
          chmod -R +w $out
          find $out -name cabal.project.freeze -delete -o -name package.yaml -delete
          grep -RF -- -external-libsodium-vrf $out | cut -d: -f1 | sort --uniq | xargs -n1 -- sed -r s/-external-libsodium-vrf//g -i
          ( cd $out && patch -p1 -i ${./ogmios-6-1-0--missing-srp-hash.patch} ; )
        '';
        nodeFlake = inputs.self.outputs.packages.${system}."cardano-node-8-8-0-pre--flake";
        inherit (nodeFlake.legacyPackages.${system}) haskell-nix;
        project = haskell-nix.project {
          compiler-nix-name = "ghc963";
          projectFileName = "cabal.project";
          inputMap = { "https://input-output-hk.github.io/cardano-haskell-packages" = nodeFlake.inputs.CHaP; };
          src = patched + "/server";
          modules = [ ({ lib, pkgs, ... }: {
            packages.cardano-crypto-praos.components.library.pkgconfig = lib.mkForce [ [ pkgs.libsodium-vrf ] ];
            packages.cardano-crypto-class.components.library.pkgconfig = lib.mkForce [ ([ pkgs.libsodium-vrf pkgs.secp256k1 ]
              ++ (if pkgs ? libblst then [pkgs.libblst] else [])) ];
            packages.ogmios.components.library.preConfigure = "export GIT_SHA=${inputs.${input}.rev}";
          }) ];
        };
        ogmios = project.hsPkgs.ogmios.components.exes.ogmios;
      in [
        { name = "${input}"; value = ogmios; }
        {
          name = "${input}--oci";
          value = let
            pkgs = nodeFlake.legacyPackages.${system};
          in retagOCI "ogmios" "v${version}" (pkgs.dockerTools.buildImage {
            name = "ogmios";
            tag = "v${version}";
            config = {
              ExposedPorts = {
                "1337/tcp" = {};
              };
              Labels = {
                description = "A JSON WebSocket bridge for cardano-node.";
                name = "ogmios";
              };
              Entrypoint = [ "/bin/ogmios" ];
              StopSignal = "SIGINT";
              Healthcheck = {
                Test = [ "CMD-SHELL" "/bin/ogmios health-check" ];
                Interval = 10000000000;
                Timeout = 5000000000;
                Retries = 1;
              };
            };
            copyToRoot = pkgs.buildEnv {
              name = "ogmios-env";
              paths = [ ogmios ] ++ (with pkgs; [ busybox ]);
              postBuild = ''
                cp -r ${patched}/server/config/network $out/config
              '';
            };
          });
        }
      ])

      ++

      (let
        input = "cardano-db-sync-13-1-0-0";
        version = (builtins.fromJSON (builtins.readFile ./flake.lock)).nodes.${input}.original.ref;
        theFlake = (import inputs.flake-compat {
          src = enableAArch64 {
            original = inputs.${input};
            supportedSystemsPath = "supported-systems.nix";
            extraPatch = ''
              (
                cd $out
                patch -p1 -i ${./cardano-db-sync-13.1.0.0--run-as-root.patch}
              )
            '';
          };
          override-inputs.customConfig = { outputs = {}; } // (import inputs.flake-compat {
            src = builtins.path {
              path = "${inputs.${input}}/custom-config";
            };
          }).defaultNix;
        }).defaultNix;
      in [
        # { name = "${input}--flake"; value = theFlake; }
        { name = "${input}--oci"; value = retagOCI "cardano-db-sync" version theFlake.packages.${system}.dockerImage; }
      ])

      ++

      (let
        input = "cardano-db-sync-sancho-4-0-0";
        version = (builtins.fromJSON (builtins.readFile ./flake.lock)).nodes.${input}.original.ref;
        theFlake = (import inputs.flake-compat {
          src = enableAArch64 {
            original = inputs.${input};
            supportedSystemsPath = "supported-systems.nix";
            extraPatch = ''
              (
                cd $out
                patch -p1 -i ${./cardano-db-sync-sancho-4-0-0--run-as-root.patch}
                # <https://github.com/IntersectMBO/cardano-db-sync/pull/1660>
                patch -p1 -i ${./cardano-db-sync-sancho-4-0-0--dont-use-cardano-parts.diff}
                patch -p1 -i ${./cardano-db-sync-sancho-4-0-0--enable-aarch64-linux.patch}
              )
            '';
          };
          override-inputs.customConfig = { outputs = {}; } // (import inputs.flake-compat {
            src = builtins.path {
              path = "${inputs.${input}}/custom-config";
            };
          }).defaultNix;
        }).defaultNix;
      in [
        # { name = "${input}--flake"; value = theFlake; }
        { name = "${input}--oci"; value = retagOCI "cardano-db-sync" version theFlake.packages.${system}.cardano-db-sync-docker; }
      ])

      ++

      # ——————————————————  cardano-node   —————————————————— #

      (let
        input = "cardano-node-1-35-5";
        version = (builtins.fromJSON (builtins.readFile ./flake.lock)).nodes.${input}.original.ref;
        theFlake = (import inputs.flake-compat {
          src = enableAArch64 {
            original = inputs.${input};
            supportedSystemsPath = "nix/supported-systems.nix";
            extraPatch = ''
              sed -r '
                s/"-fexternal-interpreter"//g
              ' -i $out/nix/haskell.nix
            '';
          };
        }).defaultNix;
      in [
        { name = "${input}--flake"; value = theFlake; }
        # { name = "${input}--cardano-node"; value = theFlake.packages.${system}.cardano-node; }
        # { name = "${input}--cardano-submit-api"; value = theFlake.packages.${system}.cardano-submit-api; }
        { name = "${input}--oci"; value = retagOCI "cardano-node" version theFlake.legacyPackages.${system}.dockerImage; }
        { name = "${input}--oci-submit-api"; value = retagOCI "cardano-submit-api" version theFlake.legacyPackages.${system}.submitApiDockerImage; }
      ])

      ++

      (let
        input = "cardano-node-1-35-7";
        version = (builtins.fromJSON (builtins.readFile ./flake.lock)).nodes.${input}.original.ref;
        theFlake = (import inputs.flake-compat {
          src = enableAArch64 {
            original = inputs.${input};
            supportedSystemsPath = "nix/supported-systems.nix";
          };
        }).defaultNix;
      in [
        # { name = "${input}--flake"; value = theFlake; }
        # { name = "${input}--cardano-node"; value = theFlake.packages.${system}.cardano-node; }
        # { name = "${input}--cardano-submit-api"; value = theFlake.packages.${system}.cardano-submit-api; }
        { name = "${input}--oci"; value = retagOCI "cardano-node" version theFlake.legacyPackages.${system}.dockerImage; }
        { name = "${input}--oci-submit-api"; value = retagOCI "cardano-submit-api" version theFlake.legacyPackages.${system}.submitApiDockerImage; }
      ])

      ++

      (let
        input = "cardano-node-8-8-0-pre";
        version = (builtins.fromJSON (builtins.readFile ./flake.lock)).nodes.${input}.original.ref;
        theFlake = (import inputs.flake-compat {
          src = enableAArch64 {
            original = inputs.${input};
            supportedSystemsPath = "nix/supported-systems.nix";
            extraPatch = ''
              sed -r '
                s/"ghc8107"/"ghc963"/g
                s/"-fexternal-interpreter"//g
              ' -i $out/nix/haskell.nix
            '';
          };
        }).defaultNix;
      in [
        { name = "${input}--flake"; value = theFlake; }
        # { name = "${input}--cardano-node"; value = theFlake.packages.${system}.cardano-node; }
        # { name = "${input}--cardano-submit-api"; value = theFlake.packages.${system}.cardano-submit-api; }
        { name = "${input}--oci"; value = retagOCI "cardano-node" version theFlake.legacyPackages.${system}.dockerImage; }
        { name = "${input}--oci-submit-api"; value = retagOCI "cardano-submit-api" version theFlake.legacyPackages.${system}.submitApiDockerImage; }
      ])

      ++

      (let
        input = "cardano-node-8-9-0";
        version = (builtins.fromJSON (builtins.readFile ./flake.lock)).nodes.${input}.original.ref;
        theFlake = (import inputs.flake-compat {
          src = enableAArch64 {
            original = inputs.${input};
            supportedSystemsPath = "nix/supported-systems.nix";
            extraPatch = ''
              sed -r '
                s/"ghc8107"/"ghc963"/g
                s/"-fexternal-interpreter"//g
              ' -i $out/nix/haskell.nix
            '';
          };
        }).defaultNix;
      in [
        # { name = "${input}--flake"; value = theFlake; }
        # { name = "${input}--cardano-node"; value = theFlake.packages.${system}.cardano-node; }
        # { name = "${input}--cardano-submit-api"; value = theFlake.packages.${system}.cardano-submit-api; }
        { name = "${input}--oci"; value = retagOCI "cardano-node" version theFlake.legacyPackages.${system}.dockerImage; }
        { name = "${input}--oci-submit-api"; value = retagOCI "cardano-submit-api" version theFlake.legacyPackages.${system}.submitApiDockerImage; }
      ])

    );
  };
}
