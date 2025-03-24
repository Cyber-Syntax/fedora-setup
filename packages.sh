#!/usr/bin/env bash

CORE_PACKAGES=(
  zsh-autosuggestions
  zsh-syntax-highlighting
  zsh
  vim
  ufw
  zoxide
  eza
  fd-find
  trash-cli
  lm_sensors
  htop
  btop
  pip
  keepassxc
  neovim
  vim
  luarocks
  cargo
  bash-language-server
  syncthing
  borgbackup
  seahorse
  xournalpp
  kitty
  ruff
  flatpak
  bat
  git
  fzf
)

DESKTOP_PACKAGES=(
  virt-manager # Virtualization manager
  libvirt      # Virtualization toolkit
  nvidia-open
  gdm # Display manager; adjust if switching
  sysbench
)

LAPTOP_PACKAGES=(
  # cbatticon # not on dnf
  powertop # Power management
  tlp      # Power management
  tlp-rdw
  thinkfan
)

FLATPAK_PACKAGES=(
  org.signal.Signal
  io.github.martchus.syncthingtray
  com.tutanota.Tutanota
  # Proprietary softwares
  md.obsidian.Obsidian
  com.spotify.Client
)
