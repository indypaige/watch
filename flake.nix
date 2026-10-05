{
  description = "Watch a Nix-built static site and serve it with miniserve";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
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

            echo "[watch] building $target"

            out="$(
              nix build \
                --no-link \
                --print-out-paths \
                "$target"
            )"

            mkdir -p .serve

            rsync \
              --archive \
              --delete \
              "$out/" \
              .serve/

            echo "[watch] rebuilt"
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
              if [ -n "''${server_pid:-}" ]; then
                kill "$server_pid" 2>/dev/null || true
              fi
            }

            trap cleanup EXIT INT TERM

            #
            # Initial build
            #
            rebuild-site "$target"

            #
            # Start HTTP server
            #
            echo "[watch] serving http://localhost:$port"

            miniserve .serve \
              --port "$port" \
              --index index.html &

            server_pid=$!

            #
            # Watch source files.
            #
            # .serve must be ignored because rebuild-site writes into it.
            #
            watchexec \
              --watch . \
              --ignore '.serve' \
              --ignore '.serve/**' \
              --ignore 'result' \
              --ignore 'result/**' \
              --ignore '.git' \
              --ignore '.git/**' \
              --ignore '*.swp' \
              --ignore '*~' \
              --debounce 100ms \
              -- \
              rebuild-site "$target"
          '';
        };
      in {
        packages = {
          default = watch;

          inherit
            watch
            rebuild;
        };

        apps = {
          default = {
            type = "app";
            program = "${watch}/bin/watch";
          };

          watch = {
            type = "app";
            program = "${watch}/bin/watch";
          };

          rebuild = {
            type = "app";
            program = "${rebuild}/bin/rebuild-site";
          };
        };
      });
}
