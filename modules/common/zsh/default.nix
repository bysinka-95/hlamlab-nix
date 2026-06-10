{ pkgs, ... }:

{
  # Set Zsh as the global system default shell
  users.defaultUserShell = pkgs.zsh;

  # --- CLI Tool Packages & Integrations ---
  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.fzf = {
    fuzzyCompletion = true;
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    enableZshIntegration = true;
  };

  # --- Zsh Configuration (System-Wide, WSL-Headless Optimized) ---
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    enableGlobalCompInit = true;
    enableLsColors = true;
    vteIntegration = true;

    # Syntax Highlighting Configurations
    syntaxHighlighting.enable = true;

    # Smart Auto-suggestions
    autosuggestions = {
      enable = true;
      async = true;
    };

    # Oh My Zsh Engine Setup
    ohMyZsh = {
      enable = true;
      plugins = [
        "git"
        "sudo"
        "colored-man-pages" # Adds readable ANSI syntax colors to manual pages
        "extract" # Universal unarchiver shortcut (extracts any extension type)
      ];
      theme = ""; # Left blank so Powerlevel10k takes full priority
    };

    # Global Shell Aliases
    shellAliases = {
      # NixOS Administrative Actions
      nixclean = "sudo nix-collect-garbage && sudo nix-collect-garbage -d";

      # Modernized Core Utilities (Requires eza package)
      ls = "eza --icons=always --group-directories-first";
      ll = "eza -lh --icons=always --group-directories-first";
      la = "eza -lah --icons=always --group-directories-first";
      tree = "eza --tree --icons=always";

      # Bat Enhancements (Requires bat package)
      cat = "bat --style=plain --paging=never";
      less = "bat";
      preview = "bat --style=numbers --color=always";
    };

    # Custom Shell Environment Tweaks
    setOptions = [
      "HIST_IGNORE_DUPS"
      "HIST_IGNORE_SPACE"
      "SHARE_HISTORY"
    ];

    shellInit = ''
      # Modern interactive tab-completion menu navigation via arrow keys
      zstyle ':completion:*' menu select

      # Skip the Zsh new user configuration wizard
      zsh-newuser-install() { : }

      # Enable Powerlevel10k instant prompt. Should stay close to the top of shell init.
      if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
        source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
      fi
    '';

    interactiveShellInit = ''
      # Manually source the history-substring-search script from the Nix store path
      source ${pkgs.zsh-history-substring-search}/share/zsh-history-substring-search/zsh-history-substring-search.zsh

      # Dedicated keybindings to navigate history via typed strings (Up/Down arrows)
      bindkey '^[[A' history-substring-search-up
      bindkey '^[[B' history-substring-search-down

      # Configure FZF environment variables safely inside the interactive layer
      export FZF_CTRL_T_OPTS="--preview 'bat --color=always --line-range :50 {}'"
    '';

    # Deterministic P10k theme hooks
    promptInit = ''
      # Disable the p10k configuration wizard to prevent unwanted interactive prompts
      export POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true

      # Source your local p10k styling profile configuration
      source ${./p10k/p10k.zsh}

      # Source the underlying powerlevel10k framework theme binary
      source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme
    '';
  };
}
