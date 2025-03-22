#!/bin/bash
# Author: Cyber-Syntax
# License: BSD 3-Clause
# Comprehensive installation and configuration script for dnf-based systems.
#
# Additional functions can be run via command‑line options.
#
# Options:
#   -a    Do everything (run all additional functions).
#   -F    Install Flatpak packages.
#   -l    Install Librewolf browser.
#   -q    Install Qtile packages.
#   -b    Install Brave Browser.
#   -r    Enable RPM Fusion repositories.
#   -s    Setup system services (borgbackup, trash-cli).
#   -d    Speed up DNF (update /etc/dnf/dnf.conf with pkg_gpgcheck and max_parallel_downloads).
#   -x    Swap ffmpeg-free with ffmpeg.
#   -f    Overwrite configuration files (boot, GDM, sysctl, sudoers).
#   -h    Display this help message.
#
# Example (run as root):
#   sudo ./script.sh -a
#

# Bash settings for strict error checking.
set -euo pipefail
IFS=$'\n\t'

# Check if the script is run as root.
check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root. Use sudo or switch to root." >&2
    exit 1
  fi
}

# Help message
usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Use this script to install and configure packages on Fedora-based systems.

Options:
  -a    Do everything (execute all additional functions).
  -F    Install Flatpak packages.
  -l    Install Librewolf browser.
  -q    Install Qtile packages.
  -b    Install Brave Browser.
  -r    Enable RPM Fusion repositories.
  -s    Setup system services (borgbackup, trash-cli).
  -d    Speed up DNF ( e.g max_parallel_downloads=10 etc. )
  -x    Swap ffmpeg-free with ffmpeg.
  -f    Overwrite configuration files (boot(timeout=0), GDM(autologin qtile), tcp-bbr, sudoers(timeout password).
  -h    Display this help message.

Example:
  sudo $0 -a
EOF
  exit 1
}

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
  #TEST:
  seahorse # GNOME keyring manager
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
  #TEST:
  sysbench
)
#TEST:
#TODO: desktop packages, laptop packages
LAPTOP_PACKAGES=(
  iw # wifi
  acpilight
  cbatticon # battery icon
  powertop
)

FLATPAK_PACKAGES=(
  org.signal.Signal
  io.github.martchus.syncthingtray
  com.tutanota.Tutanota
  # Proprietary softwares
  md.obsidian.Obsidian
  com.spotify.Client
)

install_core_packages() {
  echo "Updating repositories..."
  dnf update -y

  echo "Installing core packages..."
  for pkg in "${CORE_PACKAGES[@]}"; do
    echo "Installing $pkg..."
    dnf install -y "$pkg"
  done
  echo "Core packages installation completed."
}

install_flatpak_packages() {
  echo "Installing Flatpak packages..."
  for pkg in "${FLATPAK_PACKAGES[@]}"; do
    echo "Installing $pkg via Flatpak..."
    flatpak install -y flathub "$pkg"
  done
  echo "Flatpak packages installation completed."
}

install_librewolf() {
  echo "Installing Librewolf..."
  curl -fsSL https://repo.librewolf.net/librewolf.repo | pkexec tee /etc/yum.repos.d/librewolf.repo >/dev/null
  dnf install -y librewolf
  echo "Librewolf installation completed."
}

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
  for pkg in "${qtile_packages[@]}"; do
    echo "Installing $pkg..."
    dnf install -y "$pkg"
  done
  echo "Qtile packages installation completed."
}

install_lazygit() {
  echo "Installing Lazygit..."
  dnf copr enable atim/lazygit -y
  dnf install -y lazygit
  echo "Lazygit installation completed."
}

# Disable keyring prompt for Brave Browser.
modify_brave_desktop() {
  # local desktop_file="/usr/share/applications/brave-browser.desktop"
  #TEST: home version applications .desktop file
  local desktop_file="~/.local/share/applications/brave-browser.desktop"
  if [[ ! -f "$desktop_file" ]]; then
    echo "Error: $desktop_file not found. Please check the path."
    return 1
  fi

  # Check if the parameter is already present.
  if grep -q -- "--password-store=basic" "$desktop_file"; then
    echo "Brave desktop file already contains '--password-store basic'."
  else
    # Use sed to insert the argument after the binary path.
    sed -i 's|^\(Exec=.*brave-browser-stable\)\(.*\)|\1 --password-store=basic\2|' "$desktop_file"
    echo "Modified $desktop_file to include '--password-store=basic'."
  fi
}

install_brave() {
  echo "Installing Brave Browser..."
  dnf install -y dnf-plugins-core
  echo "Adding Brave Browser repository..."
  dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
  dnf install -y brave-browser
  echo "Brave Browser installation completed."

  echo "Modifying Brave Browser desktop file for password-store basic..."
  modify_brave_desktop
}

# Description: Enables RPM Fusion free and nonfree repositories.
enable_rpm_fusion() {
  echo "Enabling RPM Fusion repositories..."
  local fedora_version
  fedora_version=$(rpm -E %fedora)
  dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_version}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_version}.noarch.rpm"
  dnf upgrade --refresh -y
  dnf group upgrade -y core
  dnf install -y rpmfusion-free-release-tainted rpmfusion-nonfree-release-tainted dnf-plugins-core
  echo "RPM Fusion repositories enabled."
}

# Description: Sets up and enables systemd services for borgbackup and trash-cli.
service_setup() {
  echo "Setting up services for borgbackup and trash-cli..."
  cp /home/developer/Documents/scripts/desktop/borg/borgbackup-home.timer /etc/systemd/system/borgbackup-home.timer
  cp /home/developer/Documents/scripts/desktop/borg/borgbackup-home.service /etc/systemd/system/borgbackup-home.service
  cp /home/developer/Documents/scripts/desktop/trash-cli.service /etc/systemd/system/trash-cli.service
  cp /home/developer/Documents/scripts/desktop/trash-cli.timer /etc/systemd/system/trash-cli.timer
  systemctl enable --now borgbackup-home.timer
  systemctl enable --now trash-cli.timer
  echo "Service setup completed."
}

# Description: Tweaks DNF configuration to improve performance
speed_up_dnf() {
  echo "Configuring DNF for improved performance..."
  local dnf_conf="/etc/dnf/dnf.conf"
  # Backup current dnf.conf if no backup exists.
  if [[ ! -f "${dnf_conf}.bak" ]]; then
    cp "$dnf_conf" "${dnf_conf}.bak"
  fi
  # Append settings if not already present.
  grep -q '^max_parallel_downloads=20' "$dnf_conf" || echo 'max_parallel_downloads=10' >>"$dnf_conf"
  grep -q '^pkg_gpgcheck=True' "$dnf_conf" || echo 'pkg_gpgcheck=True' >>"$dnf_conf"
  grep -q '^skip_if_unavailable=True' "$dnf_conf" || echo 'skip_if_unavailable=True' >>"$dnf_conf"
  #TESTING: add other options later,
  #they are in testing now.
  # minrate=50k, timeout=15, retries=5

  echo "DNF configuration updated."
}

# Description: Swaps ffmpeg-free with ffmpeg if ffmpeg-free is installed.
ffmpeg_swap() {
  echo "Checking for ffmpeg-free package..."
  if dnf list installed ffmpeg-free &>/dev/null; then
    echo "Swapping ffmpeg-free with ffmpeg..."
    dnf swap ffmpeg-free ffmpeg --allowerasing -y
    echo "ffmpeg swap completed."
  else
    echo "ffmpeg-free is not installed; skipping swap."
  fi
}

#---------------------------------------------------------------------
# Function: setup_files
# Description: Overwrites configuration files with custom settings.
#
# This function performs the following:
#   1. Overwrites the boot file to set GRUB_TIMEOUT=0 and regenerates GRUB config.
#   2. Overwrites /etc/gdm/custom.conf with custom GDM settings.
#   3. Overwrites /etc/sysctl.d/99-tcp-bbr.conf with custom TCP/network settings and reloads sysctl.
#   4. Creates/overwrites a sudoers snippet to increase the terminal password prompt timeout.
#---------------------------------------------------------------------
setup_files() {
  echo "Setting up configuration files..."

  # 1. Boot configuration.
  local boot_file="/etc/default/boot"
  echo "Overwriting boot configuration ($boot_file) with GRUB_TIMEOUT=0..."
  echo "GRUB_TIMEOUT=0" >"$boot_file"
  echo "Regenerating GRUB configuration..."
  grub2-mkconfig -o /boot/grub2/grub.cfg

  # 2. GDM custom configuration.
  local gdm_custom="/etc/gdm/custom.conf"
  echo "Overwriting GDM configuration ($gdm_custom)..."
  cat <<EOF >"$gdm_custom"
[daemon]
WaylandEnable=false
DefaultSession=qtile.desktop
AutomaticLoginEnable=True
AutomaticLogin=developer
EOF

  # 3. Network settings for TCP/BBR.
  local tcp_bbr="/etc/sysctl.d/99-tcp-bbr.conf"
  echo "Overwriting network settings ($tcp_bbr)..."
  cat <<EOF >"$tcp_bbr"
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.wmem_max=104857000
net.core.rmem_max=104857000
net.ipv4.tcp_rmem=4096 87380 104857000
net.ipv4.tcp_wmem=4096 87380 104857000
EOF
  echo "Reloading sysctl settings..."
  sysctl --system

  # 4. Sudoers snippet to increase terminal password prompt timeout and allow borgbackup script.
  local sudoers_file="/etc/sudoers.d/terminal_timeout"
  echo "Creating/updating sudoers snippet ($sudoers_file)..."
  cat <<EOF >"$sudoers_file"
## Allow borgbackup script to run without password
developer ALL=(ALL) NOPASSWD: /opt/borg/home-borgbackup.sh

## Increase timeout on terminal password prompt
Defaults timestamp_type=global
Defaults env_reset,timestamp_timeout=20
EOF
  chmod 0440 "$sudoers_file"

  echo "Configuration files have been updated."
}

# switch to ufw from firewalld
#TODO: this need core packages add below later
switch_firewall() {
  echo "Switching to UFW from firewalld..."
  systemctl disable --now firewalld
  systemctl enable --now ufw
  echo "UFW installation completed."
}

# syncthing ufw rule setup
# manual guide: https://github.com/syncthing/syncthing/tree/main/etc/firewall-ufw
# echo this to /etc/ufw/applications.d/syncthing

#
# syncthing_manual_ufw_setup() {
#   echo "Setting up UFW rules for Syncthing..."
#   local syncthing_file="/etc/ufw/applications.d/syncthing"
#   echo "Creating UFW application files for Syncthing..."
#   cat <<EOF >"$syncthing_file"
# [syncthing]
# title=Syncthing
# description=Syncthing file synchronisation
# ports=22000|21027/udp
#
# [syncthing-gui]
# title=Syncthing-GUI
# description=Syncthing web gui
# ports=8384/tcp
# EOF
#   echo "UFW syncthing ufw preset created."
# }

ufw_setup() {
  # Firstly, do some basic setup like
  # disable incoming and enable outgoing only
  echo "Updating UFW rules..."
  ufw default deny incoming
  ufw default allow outgoing

  # allow  localhost access
  ufw allow from 192.168.1.0/16

  # enable ssh
  ufw allow ssh

  echo "Opening ports for Syncthing..."
  ufw allow 22000
  ufw allow 21027/udp
  # if 0.0.0.0:8384 than open to world else 127.0.0.1:8384 localhost
  # ufw allow 8384/tcp
  echo "Syncthing ports opened. Check UFW status with 'ufw status verbose '."
}

# Ollama setup:
#TODO: This probably need manual update
# Need to find a way to automate this
ollama_setup() {
  echo "Setting up Ollama..."
  curl -fsSL https://ollama.com/install.sh | sed s/--add-repo/addrepo/ | sh
  echo "Ollama setup completed."
}

#TODO: switch to zenpower for ryzen 5000 series
# This is not a official package, need to be careful
#TESTING: This might need to blacklist k10temp
# zenpower_setup() {
#   echo "Setting up zenpower..."
#   sudo dnf copr enable shdwchn10/zenpower3
#   sudo dnf install zenpower3 zenmonitor3
#   echo "Zenpower setup completed."
# }

#NOTE: NVIDIA-OPEN currently work. don't need to dracut --force, it is worked after some time.
# I am not %100 sure how it is worked but it is worked. Anyway, do those:
# 1. Install dependencies (Test akmod-nvidia first, if not working than use akmod-nvidia-open)
# akmod-nvidia-open -> but this is probably not working refer to:
# https://discussion.fedoraproject.org/t/how-to-switch-nvidia-open/147095/4
# swap if you already installed akmod-nvidia
#
#TODO: swap ffmpeg first

# Install CUDA
# https://rpmfusion.org/Howto/CUDA#Installation
# sudo dnf config-manager addrepo --from-repofile=https://developer.download.nvidia.com/compute/cuda/repos/fedora41/$(uname -m)/cuda-fedora41.repo
# sudo dnf clean all
# This nvidia-driver not found in fedora 41?
# sudo dnf module disable nvidia-driver
# sudo dnf config-manager setopt cuda-fedora41-$(uname -m).exclude=nvidia-driver,nvidia-modprobe,nvidia-persistenced,nvidia-settings,nvidia-libXNVCtrl,nvidia-xconfig
# sudo dnf -y install cuda-toolkit
# if it is not install, install NVEnc/NVDec support:
# xorg-x11-drv-nvidia-cuda-libs

#NOTE: macros.nvidia-kmod needed which rpm package nvidia-open can't handle it
# sudo dnf swap akmod-nvidia akmod-nvidia-open
# 2. write macros.nvidia-kmod file
# sudo sh -c 'echo "%_with_kmod_nvidia_open 1" > /etc/rpm/macros.nvidia-kmod'
# 3. rebuild with force
# sudo akmods --kernels $(uname -r) --rebuild --force
# 4. reboot and check nvidia-drm is loaded and license
#     # modinfo nvidia | grep license
#     license:        Dual MIT/GPL
#
#     # cat /proc/driver/nvidia/version
#     NVRM version: NVIDIA UNIX Open Kernel Module for x86_64  [...]

# This is default on nvidia-kmod-common
# but might work if you add /etc/modprobe.d/kernel.conf ?
# MODULE_VARIANT=kernel-open

#Also added this one to /etc/modprobe.d/nvidia-modeset.conf
# not sure is it needed or not
# options nvidia-drm modeset=1 fbdev=1

#TESTING: suspend nvidia in /etc/modprobe.d/nvidia-modeset.conf
# options nvidia-drm modeset=1 fbdev=1
# options nvidia NVreg_PreserveVideoMemoryAllocations=1
# options nvidia NVreg_TemporaryFilePath=/var/tmp
#

# to enable old powersave mode
# NVreg_PreserveVideoMemoryAllocations=0

# Default here: /lib/modprobe.d/nvidia-power-management.conf
## Save and restore all video memory allocations.
#options nvidia NVreg_PreserveVideoMemoryAllocations=1
##
## The destination should not be using tmpfs, so we prefer
## /var/tmp instead of /tmp
#options nvidia NVreg_TemporaryFilePath=/var/tmp

# check if kmod-nvidia-open compiled
# rpm -qa kmod-nvidia\*
# similar output to:
# kmod-nvidia-open-6.13.6-200.fc41.x86_64-570.124.04-1.fc41.x86_64
# if not compiled, force rebuild
# sudo akmods --rebuild --force
#NOTE: Currently fedora keep both nvidia and nvidia-open kernel modules
# Now nvidia-open is build with kmod-nvidia and akmod-nvidia-open when there is new kernel update
# ❯ rpm -qa kmod-nvidia\*
# kmod-nvidia-6.13.5-200.fc41.x86_64-570.86.16-3.fc41.x86_64
# kmod-nvidia-6.13.6-200.fc41.x86_64-570.124.04-1.fc41.x86_64
# kmod-nvidia-open-6.13.6-200.fc41.x86_64-570.124.04-1.fc41.x86_64
# ❯ sudo akmods --rebuild --force
# Checking kmods exist for 6.13.6-200.fc41.x86_64            [  OK  ]
# Building and installing nvidia-open-kmod                   [  OK  ]
# ❯ rpm -qa kmod-nvidia\*
# kmod-nvidia-6.13.5-200.fc41.x86_64-570.86.16-3.fc41.x86_64
# kmod-nvidia-6.13.6-200.fc41.x86_64-570.124.04-1.fc41.x86_64
# kmod-nvidia-open-6.13.6-200.fc41.x86_64-570.124.04-1.fc41.x86_64
# NOTE: After the rebuild force, it still keeped the old nvidia driver
# and not removed it. Need to remove it manually.

#TODO:  vaapi for nvidia RTX 20xx series
#https://fedoraproject.org/wiki/Firefox_Hardware_acceleration#Configure_VA-API_Video_decoding_on_NVIDIA
# Install NVIDIA proprietary drivers. Don't forget to install cuda/nvdec/nvenc support.
# Install ffmpeg-free from Fedora, install libavcodec-freeworld from RPM Fusion repository for H.264 decoding.
# Install nvidia-vaapi-driver from RPM Fusion repository non-free. Don't use Fedora provided libva-vdpau-driver package as it's old and broken.
# Run Firefox and force enable VA-API as it's disabled on NVIDIA by default. Go to about:config page and set media.ffmpeg.vaapi.enabled to true.
# Run Firefox with NVD_BACKEND=direct MOZ_DISABLE_RDD_SANDBOX=1 env variables.
# about:support -> look HARDWARE_VIDEO_DECODING

# 1. Install dependencies
# need cuda/nvdec/nvenc support
# packages: meson libva-devel gstreamer1-plugins-bad-freeworld nv-codec-headers nvidia-vaapi-driver gstreamer1-plugins-bad-free-devel
# sudo dnf list installed '*nvidia*'
# 2. Install nvidia-vaapi-driver
# 3. add environments to /etc/environment for nvidia-vaaapi-driver

# MOZ_DISABLE_RDD_SANDBOX=1
# LIBVA_DRIVER_NAME=nvidia

# 4.add the end of GRUB_CMDLINE_LINUX

#GRUB_CMDLINE_LINUX="... nvidia-drm.modeset=1"

# 5. update grub and tell user to reboot after 10 minutes to be make sure kernel modules builded
# sudo grub2-mkconfig -o /boot/grub2/grub.cfg
#
# Check video utilization on nvidia-settings when playing 4k video

# and uninstall nvidia-driver
# after that update boot file to use nvidia-drm.modeset=1
# test with vainfo
#FIX: vainfo command not found on fedora ?

# Delete gnome desktop environment
#TODO: remove all gnome de but keep network manager
#WARN: need to be caution in this one
# remove_gnome() {
#
# }

#TODO: need to find a way to get the latest version
# 1. Download the package. Enter:
#
# wget "https://repo.protonvpn.com/fedora-$(cat /etc/fedora-release | cut -d' ' -f 3)-stable/protonvpn-stable-release/protonvpn-stable-release-1.0.2-1.noarch.rpm"
# 2. Install the Proton VPN repository containing the new app. Run:
#
# sudo dnf install ./protonvpn-stable-release-1.0.2-1.noarch.rpm && sudo dnf check-update --refresh
# 3. Run:
#
# sudo dnf install proton-vpn-gnome-desktop

#enable openvpn for selinux
# sudo semodule -i myopenvpn.pp
#

#TODO: updates
# Run Updates
# sudo dnf autoremove -y
# sudo fwupdmgr get-devices
# sudo fwupdmgr refresh --force
# sudo fwupdmgr get-updates -y
# sudo fwupdmgr update -y

#TODO: only for desktop for now
# # Initialize virtualization
# sudo sed -i 's/#unix_sock_group = "libvirt"/unix_sock_group = "libvirt"/g' /etc/libvirt/libvirtd.conf
# sudo sed -i 's/#unix_sock_rw_perms = "0770"/unix_sock_rw_perms = "0770"/g' /etc/libvirt/libvirtd.conf
# sudo systemctl enable libvirtd
# sudo usermod -aG libvirt "$(whoami)"

# Security
##Randomize MAC address and  This could be used to track general network activity.
#TODO: keep static hostname
#sudo bash -c 'cat > /etc/NetworkManager/conf.d/00-macrandomize.conf' <<-'EOF'
#[device]
#wifi.scan-rand-mac-address=yes
#
#[connection]
#wifi.cloned-mac-address=random
#ethernet.cloned-mac-address=random
#EOF
#
#sudo systemctl restart NetworkManager

# hostname change for laptop
hostname_change() {
  echo "Changing hostname..."
  local new_hostname="fedora-laptop"
  hostnamectl set-hostname "$new_hostname"
  echo "Hostname changed to $new_hostname."
}

main() {
  check_root

  # Quick check for help options
  if [[ "$#" -eq 1 && "$1" == "-h" ]]; then
    usage
  fi

  # Initialize option flags.
  all_option=false
  flatpak_option=false
  librewolf_option=false
  qtile_option=false
  brave_option=false
  rpm_option=false
  service_option=false
  dnf_speed_option=false
  swap_ffmpeg_option=false
  config_option=false
  lazygit_option=false
  ollama_option=false

  # Process command-line options.
  while getopts "aFlLqbrsdxfoh" opt; do
    case $opt in
    a) all_option=true ;;
    F) flatpak_option=true ;;
    l) librewolf_option=true ;;
    L) lazygit_option=true ;;
    q) qtile_option=true ;;
    b) brave_option=true ;;
    r) rpm_option=true ;;
    s) service_option=true ;;
    d) dnf_speed_option=true ;;
    x) swap_ffmpeg_option=true ;;
    f) config_option=true ;;
    o) ollama_option=true ;;
    h) usage ;;
    *) usage ;;
    esac
  done

  # If no optional flags were provided, show usage and exit.
  if ! $flatpak_option && ! $librewolf_option && ! $qtile_option &&
    ! $brave_option && ! $rpm_option && ! $service_option &&
    ! $dnf_speed_option && ! $swap_ffmpeg_option && ! $config_option; then
    usage
  fi

  # Determine if core packages are needed
  local need_core_packages=false
  if $all_option || $qtile_option || $service_option; then
    need_core_packages=true
  fi

  # Optimze DNF if core packages are required
  # or the user has selected the DNF speed option.
  if $need_core_packages || $dnf_speed_option; then
    speed_up_dnf
  fi

  # Install core packages.
  if $need_core_packages; then
    install_core_packages
  fi
  #TODO: when desktop, laptop ready need if statement to handle all option call by hostname
  # like if fedora-laptop then use laptop packages else desktop packages etc.
  # also some of the setups are specific to desktop or laptop

  if $all_option; then
    echo "Executing all additional functions..."
    install_flatpak_packages
    install_librewolf
    install_qtile_packages
    install_brave
    enable_rpm_fusion
    install_lazygit
    service_setup
    ffmpeg_swap
    setup_files
  else
    echo "Executing selected additional functions..."
    if $lazygit_option; then install_lazygit; fi
    if $flatpak_option; then install_flatpak_packages; fi
    if $librewolf_option; then install_librewolf; fi
    if $qtile_option; then install_qtile_packages; fi
    if $brave_option; then install_brave; fi
    if $rpm_option; then enable_rpm_fusion; fi
    if $service_option; then service_setup; fi
    if $dnf_speed_option; then speed_up_dnf; fi
    if $swap_ffmpeg_option; then ffmpeg_swap; fi
    if $ollama_option; then ollama_setup; fi
    if $config_option; then setup_files; fi
  fi
}

# Execute main with provided command-line arguments.
main "$@"
