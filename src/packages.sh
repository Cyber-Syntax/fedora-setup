#!/usr/bin/env bash

# Source the logging module
source src/logging.sh

install_qtile_packages() {
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
  sudo dnf install -y "${qtile_packages[@]}" || {
    log_error "Failed to install Qtile packages."
    return 1
  }

}

CORE_PACKAGES=(
  curl
  wget
  ufw
  trash-cli
  syncthing
  borgbackup
  flatpak
)

APPS_PACKAGES=(
  seahorse
  xournalpp
  kitty
  keepassxc
  neovim
  vim
  pavucontrol
)

DEV_PACKAGES=(
  gh
  ruff
  lm_sensors
  htop
  btop
  pip
  zoxide
  fzf
  bat
  eza
  fd-find
  zsh-autosuggestions
  zsh-syntax-highlighting
  zsh
  luarocks
  cargo
  yarnpkg
  bash-language-server
  python3-devel
  dbus-devel
  shfmt
  ShellCheck
)

DESKTOP_PACKAGES=(
  virt-manager # Virtualization manager
  libvirt      # Virtualization toolkit
  nvidia-open
  lightdm
  sysbench
)

LAPTOP_PACKAGES=(
  # cbatticon # not on sudo dnf
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
