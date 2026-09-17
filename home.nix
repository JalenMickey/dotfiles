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
    glow        # render markdown in the terminal; also backs glow.nvim's <leader>m preview
    python3Packages.huggingface-hub  # provides the `hf` CLI used to pull MLX weights into ~/.omlx/models
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

      # Delete orphaned nvim swap files. nvim holds its .swp open for the whole
      # session, so a swap that no process has open (per lsof) belongs to a dead
      # session and is safe to remove; live ones are skipped. Clears the E325
      # "swap file already exists" prompts left behind by crashed sessions.
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
      cc = "claude --dangerously-skip-permissions";
      gc = "copilot --allow-all";
      # ^ GitHub Copilot CLI's full-autonomy shortcut, equivalent to --allow-all-tools
      #   --allow-all-paths --allow-all-urls combined. Same risk profile as cc's
      #   --dangerously-skip-permissions - no confirmation prompts.
      co = "codex --sandbox workspace-write --ask-for-approval never";
      # ^ --full-auto was removed in codex 0.128 (deprecated compat flag warned,
      #   then dropped). This is the documented like-for-like replacement - NOT
      #   --dangerously-bypass-approvals-and-sandbox, which removes the sandbox
      #   entirely rather than just skipping approval prompts.
      # ^ codex's default model lives in ~/.codex/config.toml, not here. Switched
      #   2026-07-12 from Qwen3.6-35B-A3B-8bit to mlx-community/Qwen3-Coder-Next-8bit
      #   (80B total, 3B active MoE) - newer architecture, longer native context
      #   (256K vs 32K-128K), and still only ~3B active params so generation speed
      #   stays close to the old 35B-A3B default despite the larger total size.
      #   128GB unified memory comfortably fits the 8bit quant (~85GB weights).
      oc = "omlx launch opencode --model mlx-community--Qwen3-Coder-Next-8bit";
      # ^ prefer this over `co` for local-model work: omlx writes real context-window
      #   metadata into opencode's config at launch, instead of Codex's bundled catalog
      #   guessing wrong for models it doesn't recognize (see the fallback-metadata warning)
      # ^ switched to the Coder model 2026-08-17, matching `co`. Qwen3.6-35B-A3B is a
      #   REASONING model: it spends its output budget in a <think> stream and never
      #   lands a clean tool call, which is what caused the gnhf/oc "produced no final
      #   answer" failures (see docs/agentic-workflow.md gotchas). Reasoning models are
      #   fine for chat, wrong for agentic tool-calling loops.
      # ^ this alias is not just a per-invocation choice: `omlx launch` WRITES the model
      #   into ~/.config/opencode/opencode.json, and the omlx service appears to sync its
      #   last-launched model back into that file on start. So a stale model here silently
      #   becomes the default for every opencode consumer, including firstmate crewmates
      #   that spawn `opencode` directly and never touch this alias.
      # ^ superseded rationale, kept for history: default model 2026-07-11 was
      #   Qwen3.6-35B-A3B (MoE, 3B active), which measured
      #   ~5.6x faster generation than the prior Qwen3.6-27B dense default, for a small
      #   (1-4 point, worst case ~8 on Terminal-Bench) accuracy dip per Qwen's own
      #   published benchmarks.
      # ^ 2026-09-17: Qwen3.6-27B-8bit and Qwen3.6-35B-A3B-8bit weights were DELETED
      #   (63GB reclaimed). Nothing references those model ids anymore - if you see one
      #   in a config, it is stale.

      ou = "omlx launch opencode --model Qwen3.8-27B-Uncensored-8bit";
      # ^ deep reasoning + refusal bypass, added 2026-09-17. Reach for it when a problem
      #   needs careful thought rather than speed, or when guardrails block legitimate
      #   work. NOT the coding driver - `oc` (Qwen3-Coder-Next-8bit) stays that.
      # ^ Expect ~18 tok/s vs `oc`'s ~78 (measured, see docs §5a). It is a DENSE 27B, so
      #   all 27B params are read per token and it is bandwidth-bound at ~20.8 tok/s on
      #   this machine; `oc` is an MoE activating only ~3B. The 4.3x gap is the price of
      #   this slot, and the reason it is not the default.
      # ^ Chosen over DeepSeek V4 Flash abliterated (91GB, ds4 engine) because it ties
      #   V4 Flash on the Artificial Analysis Intelligence Index (52 vs 52) at ~27.5GB
      #   instead of ~91GB, runs on MLX/omlx so this stack keeps working, and takes no
      #   Q2 quantization damage. V4 Flash wins agentic coding on paper (DeepSWE 54.4
      #   vs 42.2) but only at full precision - the 128GB-viable build is Q2 AND
      #   abliterated, which degrades exactly that advantage. Independently moot: omlx
      #   bundles mlx_lm, which ships deepseek_v2/v3/v32 but NO v4 (upstream mlx-lm
      #   issue #1281 is open), so no DeepSeek V4 MLX quant will load here at all.
      # ^ multimodal: this build carries preprocessor/video_preprocessor configs, so it
      #   takes image and video input. It is served through omlx's VLM path, which does
      #   NOT stream incrementally - the whole response arrives in one SSE chunk. Matters
      #   only for benchmarking (see docs §5a), not for interactive use.
      # ^ NO non-abliterated counterpart is installed. `mlx-community/Qwen3.8-27B-8bit`
      #   (29.5GB) was specced as a clean control for judging whether abliteration had
      #   degraded something, then deliberately deferred 2026-09-17 - the next model
      #   downloaded becomes the daily driver instead. Until then there is nothing on
      #   this machine to A/B against, so treat odd behaviour from `ou` as unattributed:
      #   it could be abliteration damage or just the model.
      # ^ model id is the DIRECTORY NAME under ~/.omlx/models, not an HF repo id.
      #   `omlx serve` discovers each subdir containing config.json + *.safetensors and
      #   names the model after the folder - hence no `mlx-community--` prefix, unlike
      #   `oc` above, which resolves from the HF cache.
      # ^ same launch-writes-config caveat as `oc`: this WRITES the model into
      #   ~/.config/opencode/opencode.json and becomes the default for every opencode
      #   consumer until something else overwrites it. Re-run `oc` to switch back.
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
