#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ln -sfn "$DIR" ~/.dotfiles
exec sudo darwin-rebuild switch --impure --flake ~/.dotfiles#mac
# ^ --impure is required: home.nix reads home/omlx-api-key.local via
#   builtins.pathExists/readFile at eval time. Nix flake evaluation is pure
#   by default, so pathExists on that absolute path silently returns false
#   without --impure - which is why OMLX_API_KEY was landing as "" in the
#   built profile even though the key file exists and is readable.
