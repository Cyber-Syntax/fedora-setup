#!/bin/bash

CORE_PACKAGES=(
  zsh-autosuggestions
  zsh-syntax-highlighting
  zsh
  vim
  ufw                  # Firewall; Fedora defaults to firewalld
  zoxide               # Enhanced directory navigation
  eza                  # Modern ls replacement
  fd-find              # Faster file search
  trash-cli            # Command-line trash utility
  lm_sensors           # Hardware sensor monitoring
  htop                 # Process viewer
  btop                 # Resource monitor
  pip                  # Python package installer
  keepassxc            # Password manager
  neovim               # Modern text editor
  vim                  # Text editor
  luarocks             # Lua package manager
  cargo                # Rust package manager
  bash-language-server # Bash language server
  syncthing            # File synchronization
  borgbackup           # Backup utility
  seahorse             # GNOME keyring manager
  xournalpp
  kitty
  # coding
  ruff
)

DESKTOP_PACKAGES=(
  virt-manager # Virtualization manager
  libvirt      # Virtualization toolkit
  nvidia-open
  gdm # Display manager; adjust if switching
  sysbench
)

LAPTOP_PACKAGES=(
  acpilight # Backlight control
  cbatticon # battery icon
  powertop  # Power management
)

FLATPAK_PACKAGES=(
  org.signal.Signal
  io.github.martchus.syncthingtray
  com.tutanota.Tutanota
  # Proprietary softwares
  md.obsidian.Obsidian
  com.spotify.Client
)
