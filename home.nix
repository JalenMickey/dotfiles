{ config, pkgs, lib, user, ... }:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
  omlxApiKeyFile = "${dotfiles}/home/omlx-api-key.local";
in

{
  home.username = user;
  home.homeDirectory = "/Users/${user}";
  home.stateVersion = "24.11";
  home.packages = with pkgs; [
    # cli i use constantly
    ripgrep   # fast search
    fd        # fast find
    fzf       # fuzzy finder
    jq        # json on the command line
    lazygit
    neovim
    nodejs_22   # node + npm/npx (needed for JS/TS projects like label-platform)
    gh          # needed by firstmate for GitHub auth/PRs
    # the font everything renders in
    nerd-fonts.hack
  ];
  fonts.fontconfig.enable = true;
  home.sessionVariables.EDITOR = "nvim";
  home.sessionVariables.OMLX_API_KEY =
    lib.optionalString (builtins.pathExists omlxApiKeyFile) (lib.strings.trim (builtins.readFile omlxApiKeyFile));
  # ^ local omlx server auth, used by Codex's omlx model_provider. Value lives in home/omlx-api-key.local
  #   (gitignored, not this public repo) so the real key is never committed.
  home.sessionPath = [ "${config.home.homeDirectory}/.local/bin" ];  # treehouse, no-mistakes installers drop binaries here

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;      # ghost text from history
    syntaxHighlighting.enable = true;  # commands turn green when valid
    initContent = ''
      bindkey '^f' autosuggest-accept
    '';
    shellAliases = {
      ".." = "cd ..";
      add = "git add .";
      push = "git push";
      pull = "git pull";
      m = "git switch main";
      cc = "claude --dangerously-skip-permissions";
      co = "codex --sandbox workspace-write --ask-for-approval never";
      # ^ --full-auto was removed in codex 0.128 (deprecated compat flag warned,
      #   then dropped). This is the documented like-for-like replacement - NOT
      #   --dangerously-bypass-approvals-and-sandbox, which removes the sandbox
      #   entirely rather than just skipping approval prompts.
      oc = "omlx launch opencode --model mlx-community--Qwen3.6-35B-A3B-8bit";
      # ^ prefer this over `co` for local-model work: omlx writes real context-window
      #   metadata into opencode's config at launch, instead of Codex's bundled catalog
      #   guessing wrong for models it doesn't recognize (see the fallback-metadata warning)
      # ^ switched default model 2026-07-11: Qwen3.6-35B-A3B (MoE, 3B active) measured
      #   ~5.6x faster generation than the prior Qwen3.6-27B dense default, for a small
      #   (1-4 point, worst case ~8 on Terminal-Bench) accuracy dip per Qwen's own
      #   published benchmarks. 27B weights kept on disk for occasional manual use via
      #   `omlx launch codex --model mlx-community--Qwen3.6-27B-8bit` when max quality
      #   matters more than speed.
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

  # Edit-in-place: the real file stays in my repo, ~/.config just points at it.
  home.file.".config/wezterm".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/wezterm";
  home.file.".config/nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/nvim";
  home.file.".config/herdr".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/herdr";
  home.file.".claude/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/settings.json";

  home.file.".claude/CLAUDE.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".codex/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".config/opencode/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
}
