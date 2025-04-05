#!/usr/bin/env bash

install_qtile_packages() {
  echo "Installing Qtile packages..."
  local qtile_packages=(
    feh
    picom
    i3lock
    rofi
    qtile-extras
    lxappearance
    gammastep
    numlockx
    dunst
    flameshot
    playerctl
    xev # X event viewer
  )
  # one line install
  dnf install -y "${qtile_packages[@]}" || {
    echo "Error: Failed to install Qtile packages." >&2
    return 1
  }

  echo "Qtile packages installation completed."
}

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
  yarnpkg
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
  pavucontrol
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
