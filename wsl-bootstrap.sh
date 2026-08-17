#!/usr/bin/env bash
#
# wsl-bootstrap.sh - stand up this environment on WSL2 (Ubuntu).
# Run this INSIDE your WSL2 distro, from a clone of this repo.
# On a Mac, use ./bootstrap.sh instead - this is the Windows/WSL2 counterpart.
#
# It automates the Nix-managed, declarative half:
#   1. sanity-check we're actually in WSL2
#   2. install Determinate Nix if missing
#   3. symlink the repo to ~/.dotfiles (home-linux.nix reads config from there)
#   4. apply home-linux.nix via home-manager
#
# The non-Nix half - local inference (Ollama), the agent CLIs, and voice - is
# NOT automated; those are printed as next steps at the end and explained in
# docs/windows-wsl2.md. This mirrors the Mac split (bootstrap.sh vs the
# "manual tools after bootstrap" README section).
set -euo pipefail

# 1. WSL2 check
if ! grep -qiE "microsoft|wsl" /proc/version 2>/dev/null; then
  echo "error: this doesn't look like WSL2. On macOS run ./bootstrap.sh instead." >&2
  exit 1
fi

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# 2. Nix (Determinate installer, same as the Mac path)
if ! command -v nix >/dev/null 2>&1; then
  echo "==> Installing Determinate Nix..."
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --determinate
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh 2>/dev/null || true
fi

# 3. Symlink the repo -> ~/.dotfiles (home-linux.nix's edit-in-place symlinks
#    resolve config through this path, exactly like the Mac profile).
ln -sfn "$DIR" "$HOME/.dotfiles"

# 4. Apply the home-manager profile. `nix run` fetches the home-manager CLI on
#    the fly, so there's no chicken-and-egg install step.
echo "==> Applying home-linux.nix via home-manager..."
nix run --extra-experimental-features "nix-command flakes" \
  home-manager/release-26.05 -- switch --flake "$HOME/.dotfiles#jalenmickey" -b backup

cat <<'NEXT'

==> Nix-managed half done. Restart the shell (exec zsh -l) to pick it up.

Manual, non-Nix pieces (full detail in docs/windows-wsl2.md):

  1. Local inference  (replaces omlx/MLX, which is Apple-only)
       curl -fsSL https://ollama.com/install.sh | sh
       ollama pull qwen2.5-coder:32b     # or a size your GPU/RAM can actually serve
     Then point the frontends at Ollama's OpenAI-compatible endpoint:
       - codex:    set base_url = "http://localhost:11434/v1" in ~/.codex/config.toml
       - opencode: add an Ollama provider at the same URL
     Reality check: local speed/size depends on this laptop's GPU + RAM, not a
     MacBook's 128GB unified memory. Expect smaller quants and more cloud (cc).

  2. Agent CLIs  (Homebrew casks on Mac; npm here - verify current package names)
       npm i -g @anthropic-ai/claude-code @openai/codex opencode-ai @github/copilot
       # use npx if your node prefix is read-only

  3. Terminal + font  (Windows side, NOT inside WSL2)
       winget install wez.wezterm
       # install Hack Nerd Font on Windows; point WezTerm at
       # this repo's home/.config/wezterm and set default_prog to launch WSL

  4. Voice input  (replaces Parakeet/OpenSuperWhisper)
       Windows Voice Typing (Win+H), or a Whisper-based Windows app

  5. Crew tools  (same manual clone as the Mac README)
       mkdir -p ~/github/kunchenguid
       git clone https://github.com/kunchenguid/firstmate ~/github/kunchenguid/firstmate
NEXT
