{ user, ... }:

{
  # Determinate already manages the Nix daemon, so nix-darwin shouldn't.
  nix.enable = false;

  nixpkgs.config.allowUnfree = true;
  nixpkgs.hostPlatform = "aarch64-darwin"; # use x86_64-darwin for Intel CPU

  system.primaryUser = user;
  users.users.${user} = {
    home = "/Users/${user}";
  };
  system.stateVersion = 6;
  system.defaults = {
    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      KeyRepeat = 2;          # fast key repeat
      InitialKeyRepeat = 15;  # short delay before repeat
      _HIHideMenuBar = true;  # auto-hide the menu bar
      AppleShowAllExtensions = true;
    };
    dock.autohide = true;
    finder.FXPreferredViewStyle = "Nlsv";  # list view by default
    finder.CreateDesktop = false;          # clean desktop
    trackpad.Clicking = true;              # tap to click
  };
  nix-homebrew = {
    enable = true;
    inherit user;
  };
  homebrew = {
    enable = true;
    onActivation.cleanup = "zap";  # remove anything not listed here
    onActivation.autoUpdate = true;
    onActivation.extraFlags = [ "--force" ];
    taps = [
      "jundot/omlx"  # private tap, trusted via `brew trust jundot/omlx`
    ];
    brews = [
      "herdr"
      "rust"              # build dep for omlx; kept explicit since omlx has no prebuilt bottle and rebuilds from source on every upgrade
      "jundot/omlx/omlx"  # local MLX inference server (LLM + voice via mlx-audio)
      "opencode"          # terminal coding agent; used for local-model work via
                          # `omlx launch opencode`, which writes correct context-window
                          # metadata for the served model instead of guessing (unlike
                          # Codex's bundled model catalog, which doesn't know local models)
    ];
    casks = [
      "wezterm"
      "claude-code"
      "codex"           # OpenAI Codex CLI, used as a coding-agent frontend for omlx
      "opensuperwhisper" # local voice dictation
    ];
  };

  # Raise the Metal/GPU wired-memory ceiling to match omlx's own internal target
  # (see ~/.omlx/settings.json process_memory_enforcer, which expects 122GB).
  # Without this, the kernel default silently resets on every reboot, so omlx
  # falls back to a lower cap than it's configured for and can hard-panic
  # instead of gracefully rejecting oversized requests.
  #
  # A plain `system.activationScripts` entry was considered but skipped: nix-darwin
  # has a known issue where activation scripts don't reliably re-run from
  # org.nixos.activate-system after reboot (only on `darwin-rebuild switch`).
  # A dedicated LaunchDaemon with RunAtLoad is loaded directly by launchd at
  # boot, independent of that daemon, so it's the more reliable path here.
  launchd.daemons."omlx-gpu-memory" = {
    serviceConfig = {
      ProgramArguments = [ "/usr/sbin/sysctl" "-w" "iogpu.wired_limit_mb=124928" ];
      RunAtLoad = true;
    };
  };
}
