# ogmios-tracker

A repo to track and build [Ogmios](https://github.com/CardanoSolutions/ogmios) on [ci.iog.io](https://ci.iog.io/project/input-output-hk-ogmios-tracker) to populate https://cache.iog.io.

Currently, versions are specified manually in [`flake.nix`](/flake.nix), but this may be automated in the future.

## Motivation

We need it to be able to quickly recompile and experiment with different [Ogmios](https://github.com/CardanoSolutions/ogmios) versions.

Especially from within [certain Dockerfiles](https://github.com/input-output-hk/cardano-js-sdk/tree/master/compose), which start with an empty `/nix/store`, and therefore take a long time to compile.
