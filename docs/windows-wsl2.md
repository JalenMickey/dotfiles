# Running this setup on Windows (WSL2)

This environment is built for macOS (nix-darwin + Homebrew + Apple-Silicon local
inference). You don't *port* it to Windows - you rebuild the same **shape** on a
Linux foundation that Windows can host: **WSL2**. The Unix-shaped ~80% runs
essentially unchanged; two pieces get swapped.

## The two things that can't come across

| Mac piece | Why it can't move | Windows/WSL2 replacement |
|---|---|---|
| **nix-darwin** | "darwin" is macOS; no Windows equivalent | **home-manager standalone** in WSL2 (`home-linux.nix`) |
| **omlx / MLX** | MLX runs only on Apple-Silicon GPUs | **Ollama** (or llama.cpp), keyed to the laptop's GPU |

Everything else is portable: WezTerm, Neovim, herdr/tmux, git, gh, the Node agent
CLIs, the axi tools, lavish, no-mistakes, treehouse, firstmate, gnhf.

## Three tiers

| Component | On Windows |
|---|---|
| WezTerm | Runs natively on **Windows**; configure it to launch into WSL2 |
| Neovim, git, gh, ripgrep/fd/fzf/jq/lazygit | Run in WSL2 unchanged (declared in `home-linux.nix`) |
| herdr (tmux-style, `Ctrl+b` prefix) | In WSL2; `tmux` is the drop-in if herdr has no Linux build |
| Claude Code, Codex, OpenCode, Copilot CLI | Node CLIs in WSL2; `cc`/`gc` are cloud, so identical |
| axi tools, lavish, no-mistakes, treehouse, firstmate, gnhf | Bash + npx in WSL2 - this is *why* WSL, not native Windows |
| Nix + home-manager | Nix runs in WSL2; **not** nix-darwin. Use `home-linux.nix` |
| Homebrew casks / macOS defaults (dock, Finder) | Replace with `winget`/Linux packages; the system defaults are N/A |
| omlx (local inference) | Swap for **Ollama/llama.cpp** |
| Parakeet v3 / OpenSuperWhisper | **Win+H** Voice Typing, or a Whisper-based Windows app |

## The real consideration: local inference is a hardware story

The software swap is clean - the agents only need an OpenAI/Anthropic-compatible
endpoint, and Ollama exposes `/v1`, so `co`/`oc` just re-point their `base_url`
from omlx to Ollama. The catch is silicon:

- **NVIDIA dGPU laptop** -> CUDA path (Ollama/llama.cpp/LM Studio) works well, but
  you'll run smaller quants than the 80B MoE this Mac serves.
- **Integrated graphics only** -> local inference is slow/limited; lean much
  harder on cloud (`cc`) and use local only for the lightest tasks.

The Mac here is an M5 Max / 128GB unified memory - a very high ceiling. A typical
Windows laptop splits far less between RAM and VRAM. The *methodology* ports
cleanly; the *zero-cost-local-90%* pillar depends on the machine's GPU + memory.

## Setup

1. **Enable WSL2 + Ubuntu** (PowerShell, admin):
   ```powershell
   wsl --install -d Ubuntu
   ```
2. **Clone the repo inside WSL2** and run the bootstrap:
   ```sh
   git clone https://github.com/JalenMickey/dotfiles.git ~/.dotfiles-src
   cd ~/.dotfiles-src
   ./wsl-bootstrap.sh
   ```
   That installs Nix, symlinks the repo to `~/.dotfiles`, and applies
   `home-linux.nix` (shell, Neovim, starship, aliases, the CLI packages, the
   edit-in-place symlinks). It then prints the manual steps below.
3. **Local inference** (replaces omlx):
   ```sh
   curl -fsSL https://ollama.com/install.sh | sh
   ollama pull qwen2.5-coder:32b     # or a size your GPU/RAM can serve
   ```
   Point the frontends at it:
   - **Codex** - in `~/.codex/config.toml`, set the provider `base_url` to
     `http://localhost:11434/v1`.
   - **OpenCode** - add an Ollama provider at the same URL. `oc` is then just
     `opencode` (no `omlx launch` wrapper).
4. **Agent CLIs** (Homebrew casks on Mac; npm here - verify current names):
   ```sh
   npm i -g @anthropic-ai/claude-code @openai/codex opencode-ai @github/copilot
   ```
5. **WezTerm + font** on the **Windows** side:
   ```powershell
   winget install wez.wezterm
   ```
   Install Hack Nerd Font on Windows, point WezTerm at this repo's
   `home/.config/wezterm`, and set `default_prog` to launch your WSL2 distro.
6. **Voice** - Windows Voice Typing (`Win+H`) or a Whisper-based Windows app.
7. **Crew tools** - same manual clone as the Mac README:
   ```sh
   git clone https://github.com/kunchenguid/firstmate ~/github/kunchenguid/firstmate
   ```

## What you keep vs. what changes

**Keep:** the whole loop - herdr/tmux panes, Neovim, the agent CLIs, the axi
tools, the crew (firstmate/treehouse/gnhf), no-mistakes, the aliases, the
edit-in-place dotfiles.

**Changes:** the inference backend (Ollama, not omlx) and the voice app - plus
a lower local-model ceiling unless the laptop has a strong GPU.

> **Status:** this is a sketch/starting point, not a battle-tested path like the
> Mac side. `home-linux.nix` and `wsl-bootstrap.sh` cover the declarative half;
> the Ollama/agent/voice wiring is manual and worth verifying against current
> tool docs when you actually set it up.
