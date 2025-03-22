#!/bin/bash
# Author: Serif Cyber-Syntax
# License: BSD 3-Clause
# Comprehensive installation and configuration script
#for dnf-based systems.

# Bash settings for strict error checking.
set -euo pipefail
IFS=$'\n\t'

# Source additional functions from separate files.
source general_func.sh
source desktop_func.sh
source general_app.sh

# VARIABLES (general used like username, borgbackup location etc.)
# NOTE: Change these variables as needed.
USER="developer"
hostname_desktop="fedora"
hostname_laptop="fedora-laptop"
boot_file="/etc/default/grub"
tcp_bbr="/etc/sysctl.d/99-tcp-bbr.conf"
sudoers_file="/etc/sudoers.d/terminal_timeout"

# borg variables
borgbackup_timer="/etc/systemd/system/borgbackup-home.timer"
borgbackup_service="/etc/systemd/system/borgbackup-home.service"
borgbackup_script="$HOME/Documents/scripts/desktop/borg/home-borgbackup.sh"
move_opt_dir="/opt/borg/home-borgbackup.sh"

# trash-cli variables
trash_cli_service="/etc/systemd/system/trash-cli.service"
trash_cli_timer="/etc/systemd/system/trash-cli.timer"

# Variable notifying the user that the script is running.
if ! id "$USER" &>/dev/null; then
  echo "WARNING: You forget to change variables according to your needs."
  # Check if user forgot to change the VARIABLES.
  if [ -n "$SUDO_USER" ]; then
    whoami="$SUDO_USER"
  else
    whoami=$(whoami)
  fi

  echo "Script USER variable is: $USER but your username: $whoami."
  echo "Please change the USER variable and other variables according to your system configuration."

  exit 1
fi

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
WARNING: I am not responsible for any damage caused by this script. 
Use it with caution. This script is need root privileges which can be dangerous.
Please, always review the script before running it.

NOTE: Please change the variables as your system configuration.

This scripts automates the installation and configuration of Fedora-based systems.

Options:
  -a    Execute all functions. (NOTE:System detection handled by hostname)
  -b    Install Brave Browser.
  -B    Setup borgbackup service.
  -t    Setup trash-cli service.
  -f    Setup useful linux configurations (boot timeout, tcp_bbr, terminal password timeout).
  -F    Install Flatpak packages.
  -l    Install Librewolf browser.
  -L    Install Lazygit.
  -q    Install Qtile packages.
  -r    Enable RPM Fusion repositories.
  -d    Speed up DNF (set max_parallel_downloads, pkg_gpgcheck, etc.).
  -x    Swap ffmpeg-free with ffmpeg.
  -u    Run system updates (autoremove, fwupdmgr commands).
WARNING: Below functions are need to tested with caution.
  -g    Remove GNOME desktop environment (keep NetworkManager).
  -z    Setup zenpower for Ryzen 5000 series
  -n    Install NVIDIA CUDA
  -N    Switch to nvidia-open drivers
  -v    Setup VA-API for NVIDIA RTX series
  -p    Install ProtonVPN repository and enable OpenVPN for SELinux
  -o    Install Ollama with its install.sh script
  -h    Display this help message.

Example:
  sudo $0 -a
EOF
  exit 1
}

# Detect system type based on hostname.
detect_system_type() {
  local hostname
  hostname=$(hostname)
  echo "Detected hostname: $hostname"

  if [[ "$hostname" == "$hostname_desktop" ]]; then
    echo "desktop"
  elif [[ "$hostname" == "$hostname_laptop" ]]; then
    echo "laptop"
  else
    echo "Error: Unknown hostname. Please check the hostname." >&2
    exit 1
  fi
}

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

install_system_specific_packages() {
  local system_type="$1"

  if [[ "$system_type" == "desktop" ]]; then
    echo "Installing desktop-specific packages..."
    for pkg in "${DESKTOP_PACKAGES[@]}"; do
      echo "Installing $pkg..."
      dnf install -y "$pkg"
    done
    echo "Desktop packages installation completed."
  elif [[ "$system_type" == "laptop" ]]; then
    echo "Installing laptop-specific packages..."
    for pkg in "${LAPTOP_PACKAGES[@]}"; do
      echo "Installing $pkg..."
      dnf install -y "$pkg"
    done
    echo "Laptop packages installation completed."
  else
    echo "Unknown system type. Skipping system-specific packages."
  fi
}

install_flatpak_packages() {
  echo "Installing Flatpak packages..."
  for pkg in "${FLATPAK_PACKAGES[@]}"; do
    echo "Installing $pkg via Flatpak..."
    flatpak install -y flathub "$pkg"
  done
  echo "Flatpak packages installation completed."
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

#TEST: Currently only for desktop
borgbackup_setup() {
  # send sh script to /opt/borg/home-borgbackup.sh
  echo "Moving borgbackup script to /opt/borg/home-borgbackup.sh..."

  # Check directory, create if not exists
  if [[ ! -d "/opt/borg" ]]; then
    mkdir -p "/opt/borg"
  fi
  # move from ~/Documents/scripts/desktop/borg/home-borgbackup.sh
  mv "$borgbackup_script" "$move_opt_dir"

  echo "Setting up borgbackup service..."
  cat <<EOF >"$borgbackup_service"
[Unit]
Description=Home Backup using BorgBackup

[Service]
Type=oneshot
ExecStart=/opt/borg/home-borgbackup.sh
EOF

  cat <<EOF >"$borgbackup_timer"
[Unit]
Description=Timer for Home Backup using BorgBackup

[Timer]
# Schedules the backup at 10:00 every day.
OnCalendar=*-*-* 10:00:00
Persistent=true
# Note: systemd timers work with local time. To follow Europe/Istanbul time, ensure your system’s timezone is set accordingly.

[Install]
WantedBy=timers.target
EOF

  echo "Reloading systemd..."
  systemctl daemon-reload
  echo "Enabling and starting borgbackup service..."
  systemctl enable --now borgbackup-home.timer
  echo "borgbackup service setup completed."

}

#TEST: Both desktop and laptop
trash_cli_setup() {
  echo "Setting up trash-cli service..."
  cat <<EOF >"$trash_cli_service"
[Unit]
Description=Trash-cli cleanup service
After=network.target
# The network dependency is optional, but good practice if your command relies on network availability.

[Service]
Type=oneshot
User=developer
# Adjust the path if trash-empty is not in /usr/bin. This command removes files older than 30 days.
ExecStart=/usr/bin/trash-empty 30

# No Restart option here because this is a one-shot service.
EOF

  cat <<EOF >"$trash_cli_timer"
[Unit]
Description=Daily timer for trash-cli cleanup

[Timer]
# Runs the service daily.
OnCalendar=daily
# Persistent makes sure that if the scheduled run was missed, it will run as soon as possible.
Persistent=true

[Install]
WantedBy=timers.target
EOF

  echo "Reloading systemd..."
  systemctl daemon-reload
  echo "Enabling and starting trash-cli service..."
  systemctl enable --now trash-cli.timer
  echo "trash-cli service setup completed."
}

# Autologin for gdm
#NOTE: currently backlog
#TODO: Need to make $USER variable
gdm_auto_login() {
  echo "Setting up autologin for GDM..."
  local gdm_custom="/etc/gdm/custom.conf"
  echo "Overwriting GDM configuration ($gdm_custom)..."
  cat <<EOF >"$gdm_custom"
[daemon]
WaylandEnable=false
DefaultSession=qtile.desktop
AutomaticLoginEnable=True
AutomaticLogin=developer
EOF
  echo "GDM autologin setup completed."
}

# Overwrites various configuration files.
# TEST: This function configures boot (GRUB), sysctl for TCP/BBR, and sudoers.
setup_files() {
  local system_type="$1"
  echo "Setting up configuration files for $system_type..."

  # 1. Boot configuration (common for both systems)
  echo "Overwriting boot configuration ($boot_file) with GRUB_TIMEOUT=0..."
  echo "GRUB_TIMEOUT=0" >"$boot_file"
  echo "Regenerating GRUB configuration..."
  grub2-mkconfig -o /boot/grub2/grub.cfg

  # 2. Autologin lightdm
  local lightdm_custom="/etc/lightdm/lightdm.conf"
  echo "Overwriting LightDM configuration ($lightdm_custom) for $system_type..."
  #autologin-session=qtile.desktop
  cat <<EOF >"$lightdm_custom"
[Seat:*]
autologin-user=developer
EOF

  #TODO: pam setup needed on lightdm
  #WARN: This need to be appended to the file
  #TEST:
  local pam_lightdm="/etc/pam.d/lightdm"
  echo "Setting up PAM configuration for LightDM..."
  cat <<EOF >>"$pam_lightdm"
auth        sufficient  pam_succeed_if.so user ingroup nopasswdlogin
auth        include     system-login
EOF

  # 3. Increase internet speed with TCP/BBR (common for both systems).

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

  # 4. Sudoers snippet (common for both systems).
  # WARN: Is it secure to give this?

  echo "Creating/updating sudoers snippet ($sudoers_file)..."
  cat <<EOF >"$sudoers_file"
## Allow borgbackup script to run without password
developer ALL=(ALL) NOPASSWD: /opt/borg/home-borgbackup.sh

## Increase timeout on terminal password prompt
Defaults timestamp_type=global
Defaults env_reset,timestamp_timeout=20
EOF
  chmod 0440 "$sudoers_file"

  echo "Configuration files have been updated for $system_type."
}

#TEST: Group for passwordless login
nopasswdlogin_group() {
  echo "Creating group for passwordless login..."
  groupadd -r nopasswdlogin 2>/dev/null || echo "Group 'nopasswdlogin' already exists."
  groupadd -r autologin 2>/dev/null || echo "Group 'autologin' already exists."
  # CHANGED: Replaced literal "username" with the USER variable for consistency.
  gpasswd -a "$USER" nopasswdlogin
  gpasswd -a "$USER" autologin
  echo "Group created for passwordless login."
  echo "Add users to the nopasswdlogin group to enable passwordless login."
  usermod -aG nopasswdlogin,autologin "$USER"
}

# Switch from firewalld to UFW.
switch_ufw_setup() {
  echo "Switching to UFW from firewalld..."
  systemctl disable --now firewalld
  systemctl enable --now ufw
  echo "UFW installation completed."
  echo "Updating UFW rules..."
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow from 192.168.1.0/16
  ufw allow ssh
  echo "Opening ports for Syncthing..."
  ufw allow 22000
  ufw allow 21027/udp
  echo "Syncthing ports opened. Check UFW status with 'ufw status verbose'."
}

# Change hostname for laptop.
laptop_hostname_change() {
  echo "Changing hostname for laptop..."
  local new_hostname="fedora-laptop"
  hostnamectl set-hostname "$new_hostname"
  echo "Hostname changed to $new_hostname."
}

# --- New functions from commented sections ---

# TEST: Remove GNOME desktop environment while keeping NetworkManager.
# This function removes common GNOME packages. It is experimental.
#WARN: Make sure this won't delete NetworkManager
#NOTE: Do not include this all_option
remove_gnome() {
  echo "Removing GNOME desktop environment..."
  # Let user confirm the removal.
  dnf remove gnome-shell gnome-session gnome-desktop
  echo "GNOME desktop environment removed. (TEST: Verify that NetworkManager is still installed.)"
}

# TEST: Setup zenpower for Ryzen 5000 series.
# This function enables the zenpower COPR repository and installs zenpower3 and zenmonitor3.
zenpower_setup() {
  echo "Setting up zenpower for Ryzen 5000 series..."
  dnf copr enable shdwchn10/zenpower3 -y
  dnf install -y zenpower3 zenmonitor3
  # blacklisting k10temp
  echo "blacklist k10temp" >/etc/modprobe.d/zenpower.conf
  echo "Zenpower setup completed. (TEST: Check if k10temp needs to be blacklisted.)"
}

# TEST: Install CUDA
nvidia_cuda_setup() {
  # https://rpmfusion.org/Howto/CUDA#Installation
  dnf config-manager addrepo --from-repofile=https://developer.download.nvidia.com/compute/cuda/repos/fedora41/$(uname -m)/cuda-fedora41.repo
  dnf clean all
  # This nvidia-driver not found in fedora 41?
  dnf module disable nvidia-driver
  dnf config-manager setopt cuda-fedora41-$(uname -m).exclude=nvidia-driver,nvidia-modprobe,nvidia-persistenced,nvidia-settings,nvidia-libXNVCtrl,nvidia-xconfig
  dnf -y install cuda-toolkit
  #TODO: check later is below package installed or not:
  #xorg-x11-drv-nvidia-cuda-libs
}

# TEST: Switch nvidia-open
switch_nvidia_open() {
  #https://rpmfusion.org/Howto/NVIDIA?highlight=%28%5CbCategoryHowto%5Cb%29#Kernel_Open
  echo "Switching to nvidia-open drivers..."
  # dnf install akmod-nvidia-open
  # dnf swap akmod-nvidia akmod-nvidia-open
  # # build the modules
  # akmods --rebuild --force

  # Rpm package not work therefore build akmod-nvidia with open
  echo "%_with_kmod_nvidia_open 1" >/etc/rpm/macros.nvidia-kmod
  # If this still not work,add --force in the end
  akmods --kernels $(uname -r) --rebuild

  #TEST: Those are probably added default by fedora on 41
  #   local modeset="/etc/modprobe.d/nvidia-modeset.conf"
  #   cat <<EOF >"$modeset"
  # options nvidia-drm modeset=1 fbdev=1
  # EOF
  # to enable old powersave mode
  # NVreg_PreserveVideoMemoryAllocations=0

  #Disable nonfree nvidia driver
  dnf --disablerepo rpmfusion-nonfree-nvidia-driver
  echo "Wait 10-20 minutes(being paronoid) for the nvidia-open modules to build than reboot. 
  Check after reboot: modinfo nvidia | grep license
  Correct output: Dual MIT/GPL 
  Also check: rpm -qa kmod-nvidia\*
  Correct output: kmod-nvidia-open-6.13.7-200.fc41.x86_64-570.124.04-1.fc41.x86_64
  "
}

# TEST: Setup VA-API for NVIDIA RTX series.
vaapi_setup() {
  echo "Setting up VA-API for NVIDIA RTX series..."
  dnf install -y meson libva-devel gstreamer1-plugins-bad-freeworld nv-codec-headers nvidia-vaapi-driver gstreamer1-plugins-bad-free-devel
  # setup vaapi for firefox
  cat <<EOF >>/etc/environment
MOZ_DISABLE_RDD_SANDBOX=1
LIBVA_DRIVER_NAME=nvidia
__GLX_VENDOR_LIBRARY_NAME=nvidia
EOF
  echo "VA-API setup completed."
}

# TEST: Install ProtonVPN repository and enable OpenVPN for SELinux.
# This function downloads the ProtonVPN repository package and installs it.
# Then it attempts to enable OpenVPN for SELinux by installing a local policy module.
install_protonvpn() {
  echo "Installing ProtonVPN repository..."
  # Note: The URL may need to be updated to the latest version.
  wget -O protonvpn.rpm "https://repo.protonvpn.com/fedora-$(awk '{print $3}' /etc/fedora-release)-stable/protonvpn-stable-release/protonvpn-stable-release-1.0.2-1.noarch.rpm"
  dnf install -y ./protonvpn.rpm && dnf check-update --refresh
  dnf install -y proton-vpn-gnome-desktop
  echo "ProtonVPN installation completed."

  echo "Enabling OpenVPN for SELinux..."
  if [[ -f "myopenvpn.pp" ]]; then
    semodule -i myopenvpn.pp
    echo "SELinux OpenVPN module installed."
  else
    echo "Warning: myopenvpn.pp not found. Please provide the SELinux policy module."
  fi
}

# TEST: Run system updates.
# This function performs cleanup and firmware update checks.
system_updates() {
  echo "Running system updates..."
  dnf autoremove -y
  fwupdmgr get-devices
  fwupdmgr refresh --force
  fwupdmgr get-updates -y
  fwupdmgr update -y
  echo "System updates completed. (TEST: Review update logs for any errors.)"
}

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

# --- Main function ---

main() {
  check_root

  # Quick check for help option.
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
  dnf_speed_option=false
  swap_ffmpeg_option=false
  config_option=false
  lazygit_option=false
  ollama_option=false
  trash_cli_option=false
  borgbackup_option=false

  # New experimental option flags.
  remove_gnome_option=false
  zenpower_option=false
  switch_nvidia_open_option=false
  nvidia_cuda_option=false
  vaapi_option=false
  protonvpn_option=false
  update_system_option=false

  # Process command-line options.
  while getopts "aFlLqbrdxfogznvpuotBh" opt; do
    case $opt in
    a) all_option=true ;;
    b) brave_option=true ;;
    B) borgbackup_option=true ;;
    d) dnf_speed_option=true ;;
    F) flatpak_option=true ;;
    f) config_option=true ;;
    l) librewolf_option=true ;;
    L) lazygit_option=true ;;
    q) qtile_option=true ;;
    r) rpm_option=true ;;
    x) swap_ffmpeg_option=true ;;
    o) ollama_option=true ;;
    g) remove_gnome_option=true ;;
    n) nvidia_cuda_option=true ;;
    N) switch_nvidia_open_option=true ;;
    v) vaapi_option=true ;;
    p) protonvpn_option=true ;;
    t) trash_cli_option=true ;;
    u) update_system_option=true ;;
    z) zenpower_option=true ;;
    h) usage ;;
    *) usage ;;
    esac
  done

  # If no optional flags were provided, show usage and exit.
  if [[ "$all_option" == "false" ]] &&
    [[ "$flatpak_option" == "false" ]] &&
    [[ "$borgbackup_option" == "false" ]] &&
    [[ "$trash_cli_option" == "false" ]] &&
    [[ "$librewolf_option" == "false" ]] &&
    [[ "$qtile_option" == "false" ]] &&
    [[ "$brave_option" == "false" ]] &&
    [[ "$rpm_option" == "false" ]] &&
    [[ "$dnf_speed_option" == "false" ]] &&
    [[ "$swap_ffmpeg_option" == "false" ]] &&
    [[ "$config_option" == "false" ]] &&
    [[ "$lazygit_option" == "false" ]] &&
    [[ "$ollama_option" == "false" ]] &&
    [[ "$remove_gnome_option" == "false" ]] &&
    [[ "$zenpower_option" == "false" ]] &&
    [[ "$nvidia_cuda_option" == "false" ]] &&
    [[ "$switch_nvidia_open_option" == "false" ]] &&
    [[ "$vaapi_option" == "false" ]] &&
    [[ "$protonvpn_option" == "false" ]] &&
    [[ "$update_system_option" == "false" ]]; then
    usage
  fi

  # Detect system type.
  system_type=$(detect_system_type)
  echo "Detected system type: $system_type"

  # Determine if core packages are needed.
  local need_core_packages=false
  if $all_option || $qtile_option || $trash_cli_option; then
    need_core_packages=true
  fi

  # Optimize DNF if core packages are required or if the user selected the DNF speed option.
  if $need_core_packages || $dnf_speed_option; then
    speed_up_dnf
  fi

  # Install core packages.
  if $need_core_packages; then
    install_core_packages
  fi

  if $all_option; then
    echo "Executing all additional functions..."

    install_system_specific_packages "$system_type"
    install_flatpak_packages
    install_librewolf
    install_qtile_packages
    install_brave
    enable_rpm_fusion
    install_lazygit
    trash_cli_setup
    ffmpeg_swap
    setup_files "$system_type"
    switch_ufw_setup

    # Experimental functions.
    install_protonvpn
    system_updates

    # System-specific additional functions.
    if [[ "$system_type" == "laptop" ]]; then
      echo "Executing laptop-specific functions..."
      laptop_hostname_change
    elif [[ "$system_type" == "desktop" ]]; then
      echo "Executing desktop-specific functions..."
      # Desktop-specific functions could be added here.
      switch_nvidia_open
      nvidia_cuda_setup
      vaapi_setup
      borgbackup_setup
      zenpower_setup #WARN: is it safe?
    fi

  else
    echo "Executing selected additional functions..."
    if $lazygit_option; then install_lazygit; fi
    if $flatpak_option; then install_flatpak_packages; fi
    if $librewolf_option; then install_librewolf; fi
    if $qtile_option; then install_qtile_packages; fi
    if $brave_option; then install_brave; fi
    if $rpm_option; then enable_rpm_fusion; fi
    if $trash_cli_option; then trash_cli_setup; fi
    if $borgbackup_setup; then borgbackup_setup; fi
    if $dnf_speed_option; then speed_up_dnf; fi
    if $swap_ffmpeg_option; then ffmpeg_swap; fi
    if $ollama_option; then install_ollama; fi
    if $config_option; then setup_files "$system_type"; fi
    if $remove_gnome_option; then remove_gnome; fi
    if $zenpower_option; then zenpower_setup; fi
    if $nvidia_cuda_option; then nvidia_cuda_setup; fi
    if $switch_nvidia_open_option; then switch_nvidia_open; fi
    if $vaapi_option; then vaapi_setup; fi
    if $protonvpn_option; then install_protonvpn; fi
    if $update_system_option; then system_updates; fi
  fi

  echo "Script execution completed."
}

# Execute main with provided command-line arguments.
main "$@"
