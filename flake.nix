{
  description = "watch";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        rebuild = pkgs.writeShellApplication {
          name = "rebuild-site";

          runtimeInputs = with pkgs; [
            nix
            rsync
          ];

          text = ''
            set -euo pipefail

            target="''${1:-.#default}"

            nix build "$target"

            mkdir -p .serve

            rsync \
              --archive \
              --delete \
              result/ \
              .serve/
          '';
        };

        watch = pkgs.writeShellApplication {
          name = "watch";

          runtimeInputs = with pkgs; [
            rebuild
            watchexec
            miniserve
          ];

          text = ''
            set -euo pipefail

            target="''${1:-.#default}"
            port="''${PORT:-8080}"

            cleanup() {
              kill "''${server_pid:-}" 2>/dev/null || true
            }

            trap cleanup EXIT INT TERM

            rebuild-site "$target"

            miniserve .serve \
              --port "$port" \
              --index index.html &

            server_pid=$!

            watchexec \
              --watch . \
              --ignore .serve \
              --ignore result \
              --ignore .git \
              --ignore '*.swp' \
              --ignore '*~' \
              --debounce 100ms \
              -- \
              rebuild-site "$target"
          '';
        };
      in {
        packages.default = watch;
        packages.watch = watch;
        packages.rebuild = rebuild;

        apps.default = {
          type = "app";
          program = "${watch}/bin/watch";
        };
      });
}
