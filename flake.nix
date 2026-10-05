{
  description = "Static site rebuild + miniserve watcher";

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

        watch-site = pkgs.writeShellApplication {
          name = "watch-site";

          runtimeInputs = with pkgs; [
            nix
            rsync
            watchexec
            miniserve
          ];

          text = ''
            set -euo pipefail

            target="''${1:-.#default}"
            port="''${PORT:-8080}"

            rebuild() {
              echo "building $target..."

              nix build "$target"

              mkdir -p .serve

              rsync \
                --archive \
                --delete \
                result/ \
                .serve/

              echo "rebuilt"
            }

            cleanup() {
              if [ -n "''${server_pid:-}" ]; then
                kill "$server_pid" 2>/dev/null || true
              fi
            }

            trap cleanup EXIT INT TERM

            rebuild

            echo "serving at http://localhost:$port"

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
              sh -c '
                nix build "'"$target"'" &&
                mkdir -p .serve &&
                rsync --archive --delete result/ .serve/
              '
          '';
        };
      in {
        packages.default = watch-site;
        packages.watch-site = watch-site;

        apps.default = {
          type = "app";
          program = "${watch-site}/bin/watch-site";
        };

        apps.watch-site = {
          type = "app";
          program = "${watch-site}/bin/watch-site";
        };
      });
}
