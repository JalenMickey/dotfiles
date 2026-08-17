# home-linux.nix - home-manager (standalone) profile for WSL2 / Linux.
#
# The Linux counterpart to home.nix. It keeps the portable core - zsh, Neovim,
# starship, aliases, the CLI packages, the edit-in-place symlinks - and drops
# everything macOS- or Apple-Silicon-specific:
#
#   - no nix-darwin / system.defaults (dock, Finder, trackpad): not applicable
#   - no Homebrew brews/casks: installed differently on Linux, see wsl-bootstrap.sh
#   - no omlx / OMLX_API_KEY: MLX is Apple-only; local inference here is Ollama
#   - no WezTerm config symlink: WezTerm runs on the *Windows* host, not in WSL2
#   - no font package: install the Nerd Font on the Windows side, for WezTerm
#
# Apply with:  home-manager switch --flake ~/.dotfiles#jalenmickey
# (wsl-bootstrap.sh wires this up on a fresh WSL2 install.)
{ config, pkgs, lib, ... }:

let
  # One line to change if this isn't your machine (mirrors flake.nix's `user`).
  user = "jalenmickey";
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
in
{
  home.username = user;
  home.homeDirectory = "/home/${user}";   # Linux path, not /Users
  home.stateVersion = "24.11";
  programs.home-manager.enable = true;      # let home-manager manage itself

  home.packages = with pkgs; [
    # same constantly-used CLI as the Mac profile
    ripgrep   # fast search
    fd        # fast find
    fzf       # fuzzy finder
    jq        # json on the command line
    lazygit
    neovim
    nodejs_22 # node + npm/npx
    gh        # GitHub auth/PRs (firstmate + the pipeline use it)
    glow      # markdown in the terminal; backs glow.nvim's <leader>m preview
    # tmux as the portable multiplexer. herdr (the Mac default) is a tmux-flavored
    # multiplexer with the same Ctrl+b prefix; if it has no Linux build, tmux is
    # the drop-in and the muscle memory carries over. Remove if you install herdr.
    tmux
  ];

  home.sessionVariables.EDITOR = "nvim";
  # No OMLX_API_KEY here: omlx/MLX don't exist on Linux. Ollama (the local
  # inference backend on WSL2) needs no key by default, so there's no secret to
  # read - which also means this profile needs no `--impure` to evaluate.
  home.sessionPath = [ "${config.home.homeDirectory}/.local/bin" ];  # treehouse/no-mistakes drop binaries here

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;      # ghost text from history
    syntaxHighlighting.enable = true;  # commands turn green when valid
    initContent = ''
      bindkey '^f' autosuggest-accept

      # Delete orphaned nvim swap files. nvim holds its .swp open for the whole
      # session, so a swap that no process has open (per lsof) belongs to a dead
      # session and is safe to remove; live ones are skipped.
      nvim-swapclean() {
        local dir="''${XDG_STATE_HOME:-$HOME/.local/state}/nvim/swap"
        [ -d "$dir" ] || { echo "no swap dir: $dir"; return 0; }
        local removed=0 inuse=0 f
        for f in "$dir"/*.swp(N); do
          if lsof -- "$f" >/dev/null 2>&1; then
            echo "in use, skipping: ''${f:t}"
            inuse=$((inuse + 1))
          elif rm -f -- "$f"; then
            echo "removed: ''${f:t}"
            removed=$((removed + 1))
          fi
        done
        echo "nvim-swapclean: $removed removed, $inuse in use"
      }
    '';
    shellAliases = {
      ".." = "cd ..";
      add = "git add .";
      push = "git push";
      pull = "git pull";
      m = "git switch main";

      # Cloud agents - identical to the Mac setup, no backend to change.
      cc = "claude --dangerously-skip-permissions";
      gc = "copilot --allow-all";

      # Local agents - same frontends, different backend. On Mac these point at
      # omlx; on Linux they point at Ollama's OpenAI-compatible endpoint
      # (http://localhost:11434/v1). Codex reads its provider from
      # ~/.codex/config.toml (set base_url there), and opencode is configured
      # with an Ollama provider - so the alias itself is just the bare frontend.
      # See docs/windows-wsl2.md for the config.toml / opencode provider blocks.
      co = "codex --sandbox workspace-write --ask-for-approval never";
      oc = "opencode";
    };
  };

  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      format = "$directory$git_branch$git_status$cmd_duration$line_break$character";
      character = {
        success_symbol = "[❯](purple)";
        error_symbol = "[❯](red)";
      };
      cmd_duration.format = "[$duration]($style) ";
    };
  };

  # Edit-in-place: the real files stay in the repo, ~/.config just points at them.
  # WezTerm is intentionally absent - it runs on the Windows host and reads its
  # config there, not inside WSL2 (see docs/windows-wsl2.md).
  home.file.".config/nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/nvim";
  home.file.".config/herdr".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/herdr";  # harmless on tmux; live if you install herdr
  home.file.".claude/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/settings.json";

  home.file.".claude/CLAUDE.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".codex/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".config/opencode/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
}
